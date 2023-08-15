# Create a new SSH key pair in local machine

ssh-keygen

# Copy the locally generated public key to your Droplet

# xx is ip address of the droplet

scp ~/.ssh/id_rsa.pub root@xxx.xx.xx.xx:/opt/id_rsa.pub

# Add the key to the authorized_keys file on the Droplet

ssh root@xxx.xx.xx.xx
cat /opt/id_rsa.pub >> ~/.ssh/authorized_keys

# Test the key by SSHing locally into the Droplet

ssh -i ~/.ssh/id_rsa root@xxx.xx.xx.xx
