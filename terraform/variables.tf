locals {
  functions_codedir_local_path = "${path.module}/../functions"
  function_names = [
    "first-function",
    "second-function"
  ]
  function_dir_local_paths                  = { for name in local.function_names : name => "${local.functions_codedir_local_path}/${name}" }
  function_package_local_paths              = { for name, path in local.function_dir_local_paths : name => "${path}/dist/index.zip" }
  function_package_base64sha256_local_paths = { for name, path in local.function_package_local_paths : name => "${path}.base64sha256" }
  function_package_s3_keys                  = { for name in local.function_names : name => "${name}/index.zip" }
  function_package_base64sha256_s3_keys     = { for name, key in local.function_package_s3_keys : name => "${key}.base64sha256.txt"}
}
