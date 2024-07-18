# OBS Deployments Happy

In this repo we will host code for deploying various of our OBS resources

## Traffic Collector Chart
This is a helm chart for deploying Astra's traffic collector in a Kubernetes environment

### For installing
1. Populate `secret.collectorId/clientId/clientSecret/tokenUrl` under values.yaml file
2. Execute the following command

```bash
helm upgrade --install traffic-collector traffic-collector-chart --values traffic-collector-chart/values.yaml --namespace <namespace to deploy in> --debug
```

## Ansible Playbooks
Under this directory we will host various ansible playbooks that can be utilized for easily deploying and configuring the VMs

## For installing
```bash
ansible-playbook -i <targetIP>, -e 'ansible_user=<ssh username>' <playbook to execute>
```
1. Install docker, if not already present, using `install-docker.yaml` file.
2. Update `collector_docker_image` under `ansible-playbooks/traffic-collector/traffic-collector.yaml` with latest docker image
   1. If you are fetching docker image from a private repository, initialize `dockerhub_username` and `dockerhub_pat` variables and uncomment `Log into DockerHub` task
3. Initialize all the required variables.
4. Execute the command