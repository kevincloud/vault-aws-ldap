#!/bin/sh
# Configures the Vault server for a database secrets demo

echo "Preparing to install Vault..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get -y update > /dev/null 2>&1
sudo apt-get -y upgrade > /dev/null 2>&1
sudo apt-get install -y unzip jq python3 python3-pip > /dev/null 2>&1
pip3 install awscli Flask hvac

mkdir /etc/vault.d
mkdir -p /opt/vault
mkdir -p /root/.aws

sudo bash -c "cat >/root/.aws/config" <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY}
aws_secret_access_key=${AWS_SECRET_KEY}
EOF
sudo bash -c "cat >/root/.aws/credentials" <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY}
aws_secret_access_key=${AWS_SECRET_KEY}
EOF

echo "Installing Vault..."
curl -sLo vault.zip ${VAULT_URL}
sudo unzip vault.zip -d /usr/local/bin/

# Server configuration
sudo bash -c "cat >/etc/vault.d/vault.hcl" <<EOF
storage "file" {
  path = "/opt/vault"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

seal "awskms" {
    region = "${AWS_REGION}"
    kms_key_id = "${AWS_KMS_KEY_ID}"
}

ui = true
EOF

# Set Vault up as a systemd service
echo "Installing systemd service for Vault..."
sudo bash -c "cat >/etc/systemd/system/vault.service" <<EOF
[Unit]
Description=Hashicorp Vault
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
Restart=on-failure # or always, on-abort, etc

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable vault
sudo systemctl start vault

export VAULT_IP=`curl -s http://169.254.169.254/latest/meta-data/public-ipv4`
export VAULT_ADDR=http://localhost:8200

sleep 5

echo "Initializing Vault..."
vault operator init -recovery-shares=1 -recovery-threshold=1 -key-shares=1 -key-threshold=1 > /root/init.txt 2>&1
cat /root/init.txt

sleep 5

echo "Extracting vault root token..."
export VAULT_TOKEN=$(cat /root/init.txt | sed -n -e '/^Initial Root Token/ s/.*\: *//p')
echo "Root token is $VAULT_TOKEN"
echo "Extracting vault recovery key..."
export RECOVERY_KEY=$(cat /root/init.txt | sed -n -e '/^Recovery Key 1/ s/.*\: *//p')
echo "Recovery key is $RECOVERY_KEY"


# echo "Setting up environment variables..."
echo "export VAULT_ADDR=http://localhost:8200" >> /home/ubuntu/.profile
echo "export VAULT_TOKEN=$VAULT_TOKEN" >> /home/ubuntu/.profile
echo "export VAULT_ADDR=http://localhost:8200" >> /root/.profile
echo "export VAULT_TOKEN=$VAULT_TOKEN" >> /root/.profile

vault audit enable syslog

vault write sys/license text=${VAULT_LICENSE}

vault secrets enable -path="secret" -version=2 kv

# Add our AWS secrets
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"data": { "aws_access_key": "${AWS_ACCESS_KEY}", "aws_secret_key": "${AWS_SECRET_KEY}" } }' \
    http://127.0.0.1:8200/v1/secret/data/aws

echo "Vault installation complete."

echo "Install LDAP server..."

sudo bash -c "cat >/root/debconf-slapd.conf" <<EOF
slapd slapd/password1 password SuperFuzz1
slapd slapd/internal/adminpw password SuperFuzz1
slapd slapd/internal/generated_adminpw password SuperFuzz1
slapd slapd/password2 password SuperFuzz1
slapd slapd/unsafe_selfwrite_acl note
slapd slapd/purge_database boolean false
slapd slapd/domain string javaperks.local
slapd slapd/ppolicy_schema_needs_update select abort installation
slapd slapd/invalid_config boolean true
slapd slapd/move_old_database boolean false
slapd slapd/backend select HDB
slapd shared/organization string JPAUTH
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/no_configuration boolean false
slapd slapd/dump_database select when needed
slapd slapd/password_mismatch note
EOF
export DEBIAN_FRONTEND=noninteractive
cat /root/debconf-slapd.conf | debconf-set-selections
sudo apt-get install -y slapd ldap-utils

mkdir -p /root/ldap/

service slapd stop
service slapd start

sleep 3

sudo bash -c "cat >/etc/ldap/slapd.d/cn\=config/cn\=schema/cn\=\{4\}custperson.ldif" <<EOF
# AUTO-GENERATED FILE - DO NOT EDIT!! Use ldapmodify.
# CRC32 5e560224
dn: cn={4}custperson
objectClass: olcSchemaConfig
cn: {4}custperson
olcObjectIdentifier: {0}cidSchema 1.3.6.1.4.1.X.Y
olcObjectIdentifier: {1}cidAttrs cidSchema:3
olcObjectIdentifier: {2}cidOCs cidSchema:4
olcAttributeTypes: {0}( cidAttrs:1 NAME 'customerId' DESC 'Customer ID' EQUA
 LITY caseIgnoreMatch SUBSTR caseIgnoreSubstringsMatch SYNTAX 1.3.6.1.4.1.14
 66.115.121.1.15{32} )
olcObjectClasses: {0}( cidOCs:1 NAME 'customerInformation' DESC 'Additional 
 Customer Information' SUP organizationalPerson STRUCTURAL MUST ( customerId
  $ uid ) )
structuralObjectClass: olcSchemaConfig
entryUUID: 8cb57776-8b83-1039-8851-1353e7ced089
creatorsName: cn=config
createTimestamp: 20191025145746Z
entryCSN: 20191025145746.517105Z#000000#000#000000
modifiersName: cn=config
modifyTimestamp: 20191025145746Z
EOF

service slapd restart

sudo bash -c "cat >/root/ldap/javaperks.ldif" <<EOF
dn: dc=javaperks,dc=local
objectClass: dcObject
objectClass: organization
dc: javaperks
o : javaperks
EOF

# add customers group
sudo bash -c "cat >/root/ldap/customers.ldif" <<EOF
dn: ou=Customers,dc=javaperks,dc=local
objectClass: organizationalUnit
ou: Customers
EOF

# Add customer #1 - Janice Thompson
sudo bash -c "cat >/root/ldap/janice_thompson.ldif" <<EOF
dn: cn=Janice Thompson,ou=Customers,dc=javaperks,dc=local
cn: Janice Thompson
sn: Thompson
objectClass: customerInformation
userPassword: SuperSecret1
uid: jthomp4423@example.com
customerId: CS100312
EOF

# Add customer #2 - James Wilson
sudo bash -c "cat >/root/ldap/james_wilson.ldif" <<EOF
dn: cn=James Wilson,ou=Customers,dc=javaperks,dc=local
cn: James Wilson
sn: Wilson
objectClass: customerInformation
userPassword: SuperSecret1
uid: wilson@example.com
customerId: CS106004
EOF

# Add customer #3 - Tommy Ballinger
sudo bash -c "cat >/root/ldap/tommy_ballinger.ldif" <<EOF
dn: cn=Tommy Ballinger,ou=Customers,dc=javaperks,dc=local
cn: Tommy Ballinger
sn: Ballinger
objectClass: customerInformation
userPassword: SuperSecret1
uid: tommy6677@example.com
customerId: CS101438
EOF

# Add customer #4 - Mary McCann
sudo bash -c "cat >/root/ldap/mary_mccann.ldif" <<EOF
dn: cn=Mary McCann,ou=Customers,dc=javaperks,dc=local
cn: Mary McCann
sn: McCann
objectClass: customerInformation
userPassword: SuperSecret1
uid: mmccann1212@example.com
customerId: CS210895
EOF

# Add customer #5 - Chris Peterson
sudo bash -c "cat >/root/ldap/chris_peterson.ldif" <<EOF
dn: cn=Chris Peterson,ou=Customers,dc=javaperks,dc=local
cn: Chris Peterson
sn: Peterson
objectClass: customerInformation
userPassword: SuperSecret1
uid: cjpcomp@example.com
customerId: CS122955
EOF

# Add customer #6 - Jennifer Jones
sudo bash -c "cat >/root/ldap/jennifer_jones.ldif" <<EOF
dn: cn=Jennifer Jones,ou=Customers,dc=javaperks,dc=local
cn: Jennifer Jones
sn: Jones
objectClass: customerInformation
userPassword: SuperSecret1
uid: jjhome7823@example.com
customerId: CS602934
EOF

# Add customer #7 - Clint Mason
sudo bash -c "cat >/root/ldap/clint_mason.ldif" <<EOF
dn: cn=Clint Mason,ou=Customers,dc=javaperks,dc=local
cn: Clint Mason
sn: Mason
objectClass: customerInformation
userPassword: SuperSecret1
uid: clint.mason312@example.com
customerId: CS157843
EOF

# Add customer #8 - Matt Grey
sudo bash -c "cat >/root/ldap/matt_grey.ldif" <<EOF
dn: cn=Matt Grey,ou=Customers,dc=javaperks,dc=local
cn: Matt Grey
sn: Grey
objectClass: customerInformation
userPassword: SuperSecret1
uid: greystone89@example.com
customerId: CS523484
EOF

# Add customer #9 - Howard Turner
sudo bash -c "cat >/root/ldap/howard_turner.ldif" <<EOF
dn: cn=Howard Turner,ou=Customers,dc=javaperks,dc=local
cn: Howard Turner
sn: Turner
objectClass: customerInformation
userPassword: SuperSecret1
uid: runwayyourway@example.com
customerId: CS658871
EOF

# Add customer #10 - Larry Olsen
sudo bash -c "cat >/root/ldap/larry_olsen.ldif" <<EOF
dn: cn=Larry Olsen,ou=Customers,dc=javaperks,dc=local
cn: Larry Olsen
sn: Olsen
objectClass: customerInformation
userPassword: SuperSecret1
uid: olsendog1979@example.com
customerId: CS103393
EOF

sudo bash -c "cat >/root/ldap/StoreUser.ldif" <<EOF
dn: cn=StoreUser,ou=Customers,dc=javaperks,dc=local
cn: StoreUser
objectClass: groupOfNames
member: cn=Janice Thompson,ou=Customers,dc=javaperks,dc=local
member: cn=James Wilson,ou=Customers,dc=javaperks,dc=local
member: cn=Tommy Ballinger,ou=Customers,dc=javaperks,dc=local
member: cn=Mary McCann,ou=Customers,dc=javaperks,dc=local
member: cn=Chris Peterson,ou=Customers,dc=javaperks,dc=local
member: cn=Jennifer Jones,ou=Customers,dc=javaperks,dc=local
member: cn=Clint Mason,ou=Customers,dc=javaperks,dc=local
member: cn=Matt Grey,ou=Customers,dc=javaperks,dc=local
member: cn=Howard Turner,ou=Customers,dc=javaperks,dc=local
member: cn=Larry Olsen,ou=Customers,dc=javaperks,dc=local
EOF

ldapadd -f /root/ldap/javaperks.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/customers.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/janice_thompson.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/james_wilson.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/tommy_ballinger.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/mary_mccann.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/chris_peterson.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/jennifer_jones.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/clint_mason.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/matt_grey.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/howard_turner.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/larry_olsen.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1
ldapadd -f /root/ldap/StoreUser.ldif -D cn=admin,dc=javaperks,dc=local -w SuperFuzz1

sudo bash -c "cat >/root/ldap/StoreUsers.hcl" <<EOF
path "secret/data/StoreUsers" {
    capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

sudo bash -c "cat >/root/1_create_policy.sh" <<EOF
vault policy write engineering /root/ldap/StoreUsers.hcl
EOF

chmod +x /root/1_create_policy.sh

sudo bash -c "cat >/root/2_enable_ldap_auth.sh" << 'EOF'
vault auth enable ldap

vault write auth/ldap/config \
    url="ldap://ldap.javaperks.local" \
    userattr="uid" \
    userdn="ou=Customers,dc=javaperks,dc=local" \
    groupdn="ou=Customers,dc=javaperks,dc=local" \
    groupfilter="(&(objectClass=groupOfNames)(member={{.UserDN}}))" \
    groupattr="cn"
    binddn="cn=admin,dc=javaperks,dc=local" \
    bindpass="SuperFuzz1"
EOF

chmod +x /root/2_enable_ldap_auth.sh

sudo bash -c "cat >/root/3_assign_policy.sh" <<EOF
vault write auth/ldap/groups/Engineering policies=Engineering
EOF

chmod +x /root/3_assign_policy.sh

sudo bash -c "cat >/root/4_validate.sh" <<EOF
unset VAULT_TOKEN
echo "Run the following command:"
echo ""
echo -e "  \e[92mvault login -method=ldap username='Jeremy Cook'\e[0m"
echo ""
echo -e "  (enter \"sheep\" for the password)"
echo ""
echo "Then run the following command:"
echo ""
echo -e "  \e[92mvault token capabilities secret/data/Engineering\e[0m"
echo ""
EOF

chmod +x /root/4_validate.sh

echo "LDAP installation complete."
