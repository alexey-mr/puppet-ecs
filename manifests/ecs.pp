#

define ecs::ecs(
  $ensure         = 'present', # 'present' | 'absent' - install or remove ECS software
  $root_password  = undef,     # root password : TODO: not used now
  $ecs_node_name  = undef,
  $vdc_name       = undef,
  $varray_name    = undef,
  $vpool_name     = undef,
  $namespace      = undef,
  $datastore_name = undef,
) {
  $node_name = $ecs_node_name ? {
    undef   => $::hostname,
    default => $ecs_node_name
  }
  $nodes_opts = "--ECSNodes ${node_name}"
  $vdc_opts = $vdc_name ? {
    undef   => '',
    default => "--VDCName ${vdc_name}"
  }
  $varray_opts = $varray_name ? {
    undef   => '',
    default => "--ObjectVArray ${varray_name}"
  }
  $vpool_opts = $vpool_name ? {
    undef   => '',
    default => "--ObjectVPool ${vpool_name}"
  }
  $namespace_opts = $namespace ? {
    undef   => '',
    default => "--Namespace ${namespace}"
  }
  $datastore_opts = $datastore_name ? { 
    undef   => '',
    default => "--DataStoreName ${datastore_name}"
  }
  Exec {
    path => ['/usr/local/bin', '/usr/sbin/', '/usr/bin', '/bin'],
  }
  file_from_source { "${title}: step2_object_provisioning.py":
    dir       => '/tmp',
    file_name => 'step2_object_provisioning.py',
  } ->
  exec { 'run ecs provisioning':
    command => "bash -c 'cd /tmp && python ./step2_object_provisioning.py ${nodes_opts} ${vdc_opts} ${varray_opts} ${vpool_opts} ${namespace_opts} ${datastore_opts}'",
    timeout => 0,
  }
}
