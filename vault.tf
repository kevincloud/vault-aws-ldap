data "template_file" "vault_setup" {
    template = "${file("${path.module}/scripts/vault_install.sh")}"

    vars = {
        AWS_ACCESS_KEY = "${var.aws_access_key}"
        AWS_SECRET_KEY = "${var.aws_secret_key}"
        AWS_REGION = "${var.aws_region}"
        AWS_KMS_KEY_ID = "${var.kms_key_id}"
        VAULT_URL = "${var.vault_dl_url}"
    }
}

resource "aws_instance" "vault-server" {
    ami = "${data.aws_ami.ubuntu.id}"
    instance_type = "${var.instance_size}"
    key_name = "${var.key_pair}"
    vpc_security_group_ids = ["${aws_security_group.vault-server-sg.id}"]
    user_data = "${data.template_file.vault_setup.rendered}"
    iam_instance_profile = "${aws_iam_instance_profile.vault-kms-unseal.id}"
    
    tags = {
        Name = "kevinc-vault-server"
    }
}

resource "aws_security_group" "vault-server-sg" {
    name = "vault-server-sg"
    description = "webserver security group"
    vpc_id = "${data.aws_vpc.primary-vpc.id}"

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 8200
        to_port = 8200
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "vault-kms-unseal" {
  statement {
    sid       = "VaultKMSUnseal"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "ec2:DescribeInstances",
      "route53:*"
    ]
  }
}

resource "aws_iam_role" "vault-kms-unseal" {
  name               = "vault-kms-role-unseal"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role.json}"
}

resource "aws_iam_role_policy" "vault-kms-unseal" {
  name   = "Vault-KMS-Unseal"
  role   = "${aws_iam_role.vault-kms-unseal.id}"
  policy = "${data.aws_iam_policy_document.vault-kms-unseal.json}"
}

resource "aws_iam_instance_profile" "vault-kms-unseal" {
  name = "vault-kms-unseal"
  role = "${aws_iam_role.vault-kms-unseal.name}"
}