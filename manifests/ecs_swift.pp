#
# TODO: move into separate puppet module

class ecs::ecs_swift(
  $ensure           = 'present',  # 'present' | 'absent' - add or remove ECS Keystone Auth providers
  $ecs_address      = undef,      # address of ECS node to connect to
  $root_password    = undef,      # root password to set
  $os_auth_url      = undef,      # OpenStack auth address for ECS Keystone Auth provider
  $os_auth_user     = undef,      # OpenStack user name for ECS Keystone Auth provider
  $os_auth_password = undef,      # OpenStack user password for ECS Keystone Auth provider
) {
  if $ensure == 'present' {
    #TODO:
  } else {
    #TODO: impl removal
  }
}
