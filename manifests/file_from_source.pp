#

define ecs::file_from_source(
  $dir,
  $file_name,
)
{
  file { "${dir}/${file_name}":
    ensure => 'present',
    source => "puppet:///modules/ecs/${file_name}",
    mode   => '0644',
    owner  => 'root',
    group  => 'root',
  }
}
