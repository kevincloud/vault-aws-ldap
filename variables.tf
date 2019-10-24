variable "aws_access_key" {
    description = "AWS access key"
}

variable "aws_secret_key" {
    description = "AWS secret key"
}

variable "aws_region" {
    description = "AWS region"
}

variable "kms_key_id" {
    description = "AWS KMS Key"
}

variable "key_pair" {
    description = "Key pair to use for SSH"
}

variable "instance_size" {
    description = "Instance size"
}

variable "vault_dl_url" {
    description = "URL to download Vault Enterprise"
}
