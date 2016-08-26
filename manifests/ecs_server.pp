#

class ecs::ecs_server(
  $ensure                = 'present',                    # 'present' | 'absent' - install or remove ECS software
  $docker_image_name     = 'emccorp/ecs-software-2.2.1', # docker image  name
  $docker_image_tag      = 'latest',                     # docker image  tag
  $ecs_node_name         = undef,                        # ecs node name, hostname is used if empty
  $root_password         = undef,                        # root password to set
  $disk_devices          = undef,                        # list of devices to be prepared for storing data, e.g. '/dev/sdb,/dev/sdd'
  $nic                   = undef,                        # ethernet adapter to use in ECS
  $ip_address            = undef,                        # ip address to listen in ECS, if mpty nic is used to detect addr
  $nodes_ip_addresses    = undef,                        # list of ips of ecs nodes in cluster: '1.1.1.1,1.1.1.2', equal to ip_address if empty
  $is_community_edition  = true,                         # is community edition flag: true/false
  $force_cleanup         = undef,                        # use any non-empty string for forcing cleanup
) {
  $node_name = $ecs_node_name ? {
    undef   => $::hostname,
    default => $ecs_node_name
  }
  $required_packages = $::osfamily ? {
    'RedHat' => ['wget', 'tar', 'docker', 'xfsprogs'],
    'Debian' => ['wget', 'tar', 'docker.io', 'xfsprogs'],
  }
  $ecs_tcp_ports = [9024, 9020, 9011, 4443]
  $ecs_udp_ports = [1095, 1096, 1098, 1198, 1298, 3218, 9091, 9094, 9100, 9201, 9203, 9208, 9209, 9250, 9888]
  $ecs_folders = [
    '/ecs',
    '/host', '/host/files', '/host/data',
    '/data',
    '/var/log/vipr', '/var/log/vipr/emcvipr-object',
  ]
  $docker_image = "${docker_image_name}:${docker_image_tag}"
  if $ensure == 'present' {
    if ! $root_password or $root_password == '' {
      fail("ERROR: root password must be changed after intallation")
    }
    if ! $nic or $nic == '' {
      fail("ERROR: nic is expected to be non empty string: nic='${nic}'")
    }
    $ip = $ip_address ? {
      undef   => get_ip_by_nic($nic),
      default => $ip_address,
    }
    if ! is_ip_address($ip) {
      fail("ERROR: ip variable is not a valid ip address: ip='${ip}'")
    }
    $nodes_ips = $nodes_ip_addresses ? {
      undef   => $ip,
      default => $nodes_ip_addresses
    }
    $docker_opts = [
      '-e SS_GENCONFIG=1',
      '-v /dev/urandom:/dev/random:ro',
      '-v /ecs:/dae',
      '-v /host:/host',
      '-v /var/log/vipr/emcvipr-object:/var/log',
      '-v /data:/data',
      '--net=host',
      "--name=${node_name}",
      "${docker_image}",
    ]
    $docker_opts_str = join($docker_opts, ' ')
    File {
      owner => '444', # storageos user
      group => '444', # storageos group
    }
    Exec {
      path => ['/usr/local/bin', '/usr/sbin/', '/usr/bin', '/bin'],
    }
    exec{ 'disable selinux enforcing':
      command => "setenforce 0",
      onlyif  => 'whereis getenforce && getenforce | grep -qi "enforcing"',
    } ->
    package { $required_packages:
      ensure => $ensure,
    }
    if $force_cleanup {
      remove_ecs { 'force_ecs_cleanup':
        node_name    => $node_name,
        ecs_folders  => $ecs_folders,
        disk_devices => $disk_devices,
        require      => Package[$required_packages],
        before       => File[$ecs_folders],
      }
    }
    file { $ecs_folders:
      ensure => 'directory',
    }
    if $is_community_edition {
      file { '/data/is_community_edition':
        ensure  => file,
        content => '',
        require => File[$ecs_folders],
        before  => File['/host/data/network.json'],
      }
    }
    file { '/host/data/network.json':
      ensure  => file,
      content => template('ecs/network.json.erb'),
    } ->
    file { '/host/files/seeds':
      ensure  => file,
      content => $nodes_ips,
      require => File[$ecs_folders],
    }
    if $disk_devices and $disk_devices != '' {
      $devices = split($disk_devices, ',')
      ensure_disk { $devices:
        require => File['/host/files/seeds'],
        before  => Service['docker'],
      }
    }
    service { 'docker':
      ensure  => 'running',
      enable  => true,
      require => File['/host/files/seeds'],
    } ->
    exec { "pull ecs docker image ${docker_image}":
      command => "docker pull ${docker_image}",
      unless  => "docker images | grep -q -e '${docker_image_name}' -e '${docker_image_tag}'",
      timeout => 0,
    } ->
    exec{ "create ecs container ${node_name}":
      command => "docker create ${docker_opts_str}",
      unless  => "docker inspect '${node_name}'",
    } ->
    firewall { '001 Open ECS TCP Ports':
      dport  => $ecs_tcp_ports,
      proto  => tcp,
      action => accept,
    } ->
    firewall { '002 Open ECS UDP Ports':
      dport  => $ecs_udp_ports,
      proto  => udp,
      action => accept,
    } ->
    exec{ "start ecs container ${node_name}":
      command => "docker start '${node_name}'",
      unless  => "docker ps | grep -q '${node_name}'",
    }
    if $is_community_edition {
      $common_object_properties_patch = [
        '--expression=\'s/object.NumDirectoriesPerCoSForSystemDT=128/object.NumDirectoriesPerCoSForSystemDT=32/\'',
        '--expression=\'s/object.NumDirectoriesPerCoSForUserDT=128/object.NumDirectoriesPerCoSForUserDT=32/\'',
      ]
      $common_object_properties_patch_str = join($common_object_properties_patch, ' ')
      $ssm_object_properties_patch = [
        '--expression=\'s/object.freeBlocksHighWatermarkLevels=1000,200/object.freeBlocksHighWatermarkLevels=100,50/\'',
        '--expression=\'s/object.freeBlocksLowWatermarkLevels=0,100/object.freeBlocksLowWatermarkLevels=0,20/\'',
      ]
      $ssm_object_properties_patch_str = join($ssm_object_properties_patch, ' ')
      $docker_storageos_cmd = "docker exec -t ${node_name} su storageos -c"
      $docker_root_cmd = "docker exec -t ${node_name}"
      exec{ "container ${node_name}: patch common.object.properties":
        command => "${docker_storageos_cmd} \"sed -i ${common_object_properties_patch_str} /opt/storageos/conf/common.object.properties\"",
        require => Exec["start ecs container ${node_name}"],
      } ->
      exec{ "container ${node_name}: patch ssm.object.properties":
        command => "${docker_storageos_cmd} \"sed -i ${ssm_object_properties_patch_str} /opt/storageos/conf/ssm.object.properties\"",
      } ->
      exec{ "container ${node_name} Wait VNeST data":
        command => "${docker_root_cmd} bash -c 'while ! test -d /data/vnest/vnest-main; do sleep 1; done'",
      } ->
      exec{ "container ${node_name}: Flush VNeST data":
        command => "${docker_root_cmd} rm -rf /data/vnest/vnest-main/*",
      } ->
      exec{ "restart ecs container ${node_name}":
        command => "docker restart '${node_name}'",
        before  => File_from_source["node ${node_name}: copy license file"]
      }
    }
    $services_ports = [
      '7443',   # authsvc
      '9202',   # dashboardsvc
      '64443',  # ecs-portal
      '9011',   # objcontrolsvc
    ]
    $services_ports_count = count($services_ports)
    $grep_query_str = suffix(prefix($services_ports, ' -e \'127.0.0.1:'), '\'')
    file_from_source { "node ${node_name}: copy license file":
      dir       => '/tmp',
      file_name => 'license.lic',
      require        => Exec["start ecs container ${node_name}"],
    } ->
    exec { "node ${node_name}: wait network services start":
      command   => "test  \"`netstat -n --tcp --listen | grep -c ${grep_query_str}`\" = \"${services_ports_count}\"",
      tries     => 120,
      try_sleep => 5,
    } ->
    request { "node ${node_name}: wait license services availabe":
      address        => $ip,
      request        => '/license | grep -q "HTTP/1.1 302 Found"',
      content_type   => 'xml',
      retry          => 120,
      retry_sleep    => 5,
    } ->
    request { "node ${node_name}: wait auth services availabe":
      address        => $ip,
      request        => '/vdc/users | grep -q "HTTP/1.1 302 Found"',
      retry          => 120,
      retry_sleep    => 5,
    } ->
    request { "node ${node_name}: upload ecs license":
      address        => $ip,
      user           => 'root',
      password       => 'ChangeMe',
      method         => 'POST',
      request        => '/license | grep -q "HTTP/1.1 200 OK"',
      request_file   => '/tmp/license.lic',
      content_type   => 'xml',
      onlyif_request => '/license | grep "The product is not licensed"',
    } ->
    request { "node ${node_name}: set ecs root password":
      address        => $ip,
      user           => 'root',
      password       => 'ChangeMe',
      method         => 'PUT',
      request        => '/vdc/users/root | grep -q "HTTP/1.1 200 OK"',
      request_body   => "{\"password\":\"${root_password}\",\"isSystemAdmin\":\"true\",\"isSystemMonitor\":\"true\"}",
#      request_body   => "{\"mgmt_user_info_update\":{\"password\": \"${root_password}\",\"isSystemAdmin\":\"true\",\"isSystemMonitor\":\"true\"}}",
      onlyif_request => '/vdc/users/root | grep -q "HTTP/1.1 200 OK"',
      require        => Exec["start ecs container ${node_name}"],
    } ->
    request { "node ${node_name}: check root password":
      address        => $ip,
      user           => 'root',
      password       => $root_password,
      request        => '/vdc/users/root | grep -q "HTTP/1.1 200 OK"',
    }
    #TODO: add autostart of ecs docker container
  } else {
    remove_ecs { "node ${node_name}: ensure_ecs_absent":
      node_name    => $node_name,
      ecs_folders  => $ecs_folders,
      disk_devices => $disk_devices,
    }
  }
}

define remove_ecs(
  $node_name,
  $ecs_folders,
  $disk_devices,
) {
  $folders_to_cleanup = join($ecs_folders, ' ')
  $rm_ecs_container_resource_name = "${title}: cleanup ecs container ${node_name}"
  $rm_ecs_folder_resource_name = "${title}: cleanup ecs container ${node_name} folder"
  Exec {
    path => [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
  }
  exec { $rm_ecs_container_resource_name:
    command => "docker rm -f -v '${node_name}'",
    onlyif  => "docker ps --all | grep -q '${node_name}'",
  }
  if $disk_devices and $disk_devices != '' {
    $cleanup_devices = suffix(split($disk_devices, ','), ":${title}")
    ensure_disk { $cleanup_devices:
      ensure  => 'absent',
      require => Exec[$rm_ecs_container_resource_name],
      before  => Exec[$rm_ecs_folder_resource_name],
    }
  }
  exec { $rm_ecs_folder_resource_name:
    command => "rm -rf $folders_to_cleanup",
    require => Exec[$rm_ecs_container_resource_name],
  }
}

define ensure_disk(
  $ensure = 'present',
  $fstype = 'xfs',
) {
  $parsed_device = split($title, ':')
  $device = $parsed_device[0]
  $split_device_name = split($device, '/')
  $mount_path = "/ecs/${split_device_name[2]}-1"
  $ecs_volume_marker = "${mount_path}/ecs_data_volume_mark_file"
  $ecs_marker_content = 'af70aa18-6bd8-4f24-b310-0c7f4144b4d0'
  File {
    owner => '444',
    group => '444',
  }
  Exec {
    path => [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
  }
  if $ensure == 'present' {
    exec { "device ${device} cleanup":
      command => "bash -c 'for i in \$(parted ${device} print | awk \"/^ [0-9]+/ {print(\\\$1)}\"); do parted ${device} rm \$i; done'",
      unless  => "test -f ${ecs_volume_marker}",
    } ->
    exec { "device ${device} make part":
      command => "bash -c 'echo \"o\nn\np\n1\n\n\nw\" | fdisk ${device}'",
      unless  => "test -f ${ecs_volume_marker}",
    } ->  
    exec { "device ${device}1 make fs":
      command => "mkfs -t ${fstype} -f ${device}1",
      unless  => "test -f ${ecs_volume_marker}",
    } ->
    file { $mount_path:
      ensure  => 'directory',
    }->
    mount { "$ensure $mount_path":
      ensure  => 'mounted',
      name    => $mount_path,
      device  => "${device}1",
      fstype  => $fstype,
      options => 'defaults',
      atboot  => true,
    } ->
    file { $ecs_volume_marker:
      ensure  => file,
      content => $ecs_marker_content,
    }
  } else {
    exec { "disable automount $mount_path":
      command => "grep -v '$mount_path' /etc/fstab > /tmp/fstab.tmp && mv /tmp/fstab.tmp /etc/fstab",
      onlyif  => "grep -q '$mount_path' /etc/fstab",
    } ->
    exec { "unmount $mount_path":
      command => "umount $mount_path",
      onlyif  => "mount | grep -q '$mount_path'",
    }
  }
}
