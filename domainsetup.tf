resource "aws_route53_zone" "labzone" {
    name = "javaperks.local"

    vpc {
        vpc_id = "${data.aws_vpc.primary-vpc.id}"
    }
}

resource "aws_route53_record" "ldaphost" {
    zone_id = "${aws_route53_zone.labzone.zone_id}"
    name    = "ldap"
    type    = "A"
    ttl     = "300"
    records = ["${aws_instance.vault-server.private_ip}"]
}
