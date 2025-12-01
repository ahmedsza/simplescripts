# this scenario is based on usign an internal load balancer.

# nginx from docker hub
kubectl create namespace internalsimple

kubectl apply -f i_simpleingress.yaml -n internalsimple
kubectl apply -f i_nginxsimple.yaml -n internalsimple
kubectl apply -f i_nginxsimpleingess.yaml -n internalsimple

kubectl get ingress -n internalsimple
kubectl get pods -n internalsimple  


# if docker is blocked by firewall, you can import image to your ACR first
$acrName = "yourACRName"
az acr import --name $acrName --source docker.io/library/nginx:1.26.1 --image nginx:1.26.1

kubectl create namespace internalsimple
kubectl apply -f i_simpleingress.yaml -n internalsimple
# update nginxsimplewithACR.yaml with your ACR info before running below commands
kubectl apply -f i_nginxsimplewithACR.yaml -n internalsimple
kubectl apply -f i_nginxsimpleingess.yaml -n internalsimple

kubectl get ingress -n internalsimple
kubectl get pods -n internalsimple