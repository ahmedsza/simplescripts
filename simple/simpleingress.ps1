# nginx from docker hub
kubectl create namespace simple

kubectl apply -f nginxsimple.yaml -n simple
kubectl apply -f nginxsimpleingess.yaml -n simple

kubectl get ingress -n simple
kubectl get pods -n simple


# if docker is blocked by firewall, you can import image to your ACR first
$acrName = "yourACRName"
az acr import --name $acrName --source docker.io/library/nginx:1.26.1 --image nginx:1.26.1

kubectl create namespace simple

# update nginxsimplewithACR.yaml with your ACR info before running below commands
kubectl apply -f nginxsimplewithACR.yaml -n simple
kubectl apply -f nginxsimpleingess.yaml -n simple

kubectl get ingress -n simple
kubectl get pods -n simple