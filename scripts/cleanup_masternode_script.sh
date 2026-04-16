sudo docker volume ls -f name=ucp- -f name=mke; sudo docker config ls -f name=ucp- -f name=mke; sudo docker service ls -f name=ucp- -f name=mke; sudo docker secret ls -f name=ucp- -f name=mke; sudo docker container ls -a -f name=ucp- -f name=mke
sudo docker service rm $(sudo docker service ls -q -f name=ucp- -f name=mke)
sudo docker network rm $(sudo docker network ls -q -f name=ucp- -f name=mke)
sudo docker container rm -f $(sudo docker container ls -qa -f name=ucp- -f name=k8s -f name=mke)
sudo docker volume rm $(sudo docker volume ls -q -f name=ucp- -f name=mke-containers -f name=mke)
sudo docker config rm $(sudo docker config ls -q -f name=com.docker.ucp -f name=mke)
sudo docker secret rm $(sudo docker secret ls -q -f name=ucp -f name=mke)
docker swarm leave --force
ENGINE=$(sudo docker version -f '{{.Server.Version}}'); echo $ENGINE
DOCKERROOTDIR=$(sudo docker info -f '{{.DockerRootDir}}'); echo $DOCKERROOTDIR
sudo systemctl stop docker; sudo systemctl status docker
sudo systemctl stop containerd; sudo systemctl status containerd
sudo rm -rf /var/lib/docker/* /etc/cni/* /etc/containerd/* /var/lib/containerd/* /var/lib/kubelet/* /var/lib/docker-engine/* /var/lib/docker/swarm/*
sudo systemctl start containerd; sudo systemctl status containerd
sudo systemctl start docker; sudo systemctl status docker
sudo docker volume ls -f name=ucp- -f name=mke; sudo docker config ls -f name=ucp- -f name=mke; sudo docker service ls -f name=ucp- -f name=mke; sudo docker secret ls -f name=ucp- -f name=mke; sudo docker container ls -a -f name=ucp- -f name=mke
