#

define ecs::request(
  $request               = undef,
  $request_body          = undef,
  $request_file          = undef,
  $content_type          = 'json',
  $method                = 'GET',
  $user                  = undef,
  $password              = undef,
  $address               = '127.0.0.1',
  $port                  = 4443,
  $onlyif_request        = undef,
  $unless_request        = undef,
  $retry                 = 3,
  $retry_sleep           = 5,
  $request_retry         = 3,
  $request_retry_deplay  = 1,
) {
  if ! $address {
    fail('ERROR: address is required')
  }
  $base_url = "https://${address}:${port}"
  $retry_opts = $request_retry ? {
    undef   => '',
    default => "--retry ${request_retry} --retry-delay ${request_retry_deplay}"
  }
  $base_cmd = "curl -ik --connect-timeout 5 ${retry_opts}"
  $login_cmd = $user ? {
    undef   => undef,
    default => "${base_cmd} -u ${user}:${password} ${base_url}/login | awk '/X-SDS-AUTH-TOKEN:/ {print(\\\$2)}'"
  }
  $headers_base = "-H 'Content-Type:application/${content_type}' -H 'ACCEPT:application/${content_type}'"
  $headers = $login_cmd ? {
    undef   => $headers_base,
    default => "${headers_base} -H \"X-SDS-AUTH-TOKEN:`${login_cmd}`\""
  }
  $conditioanl_cmd_base  = "${base_cmd} ${headers} ${base_url}"
  $onlyif_cmd = $onlyif_request ? {
    undef   => undef,
    default => "${conditioanl_cmd_base}${onlyif_request}"
  }
  $unless_cmd = $unless_request ? {
    undef   => undef,
    default => "${conditioanl_cmd_base}${unless_request}"
  }
  $data_opts = $request_body ? {
    undef   => '',
    default => "--data '${request_body}'"
  }
  $file_opts = $request_file ? {
    undef   => '',
    default => "-T ${request_file}"
  }
  $request_cmd = "${base_cmd} -X ${method} ${headers} ${file_opts} ${data_opts} ${base_url}${request}"
  exec{ "ecs request: ${title}: ${request}":
    command   => $request_cmd,
    onlyif    => $onlyif_cmd,
    unless    => $unless_cmd,
    tries     => $retry,
    try_sleep => $retry_sleep,
    path => ['/usr/local/bin', '/usr/sbin/', '/usr/bin', '/bin'],
  }
}
