#To mount the data volume
#
#1) run `sudo gdisk /dev/vdb`
#   Create a new gpt partition table
#   Create a new partition with all the defaults parameters
#   Write out
#
#2) run `sudo mkfs.ext4 /dev/vdb1` to create file system (generate UUID)
#
#3) run sudo blkid to get the UUID of /dev/vdb1
#
#Now we want to automatically mount /dev/vdb1 to /builds
#
#1) backup current /builds folder which is also ci's home folder
#   run sudo mv /builds /builds2
#
#2) recreate a /builds : run sudo mkdir /builds
#
#3) modify /etc/fstab file and add a line with
#   UUID=(the uuid that you got at the end of last part) /builds ext4 defaults 0 1
#
#4) run sudo mount -a to mount the volume
#
#5) run shopt -s dotglob && sudo mv /builds2 /builds && sudo rm -rf /builds2 && sudo chown ci: /builds
#   this will move all file from builds2 to build, including hidden files then clean up everything and give back ownership of the /build folder to the ci user
#
#6) last step is to reboot the slaves

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install git and docker
sudo apt-get install -y git docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin doxygen

# Docker post install steps
sudo groupadd docker
sudo usermod -aG docker $USER

docker pull sofaframework/sofabuilder_ubuntu:latest
