output "user_password" {
  value     = random_password.rnd_pass.result
  sensitive = true
}