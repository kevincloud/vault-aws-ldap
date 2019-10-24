output "vault-login" {
    value = "ssh -i ~/keys/${var.key_pair}.pem ubuntu@${aws_instance.vault-server.public_ip}"
}
