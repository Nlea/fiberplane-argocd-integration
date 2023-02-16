# Fiberplane-Argocd-Integration
This repo explains how to leverage [argocd-notification service's webhook](https://argocd-notifications.readthedocs.io/en/stable/services/webhook/) to create notebooks in fiberplane on certained [argocd notification triggers](https://argocd-notifications.readthedocs.io/en/stable/triggers/). 

It explains how to set up [fiberplane's daemon fpd](https://docs.fiberplane.com/docs/quickstart#set-up-the-fiberplane-daemon) to connect to prometheus in a cluster which allows to include addional metrics in the notebook

Finally the tutorial describes how to use the information from argocd and prometheus within a fiberplane template.

## Prerequisites
- A running Kubernetes Cluster (locally you can use: [kind](https://kind.sigs.k8s.io/), [minikube](https://minikube.sigs.k8s.io/docs/start/), [microk8s](https://microk8s.io/), ... ) and [kubectl](https://kubernetes.io/docs/tasks/tools/) set up
- [Argocd installed](https://argo-cd.readthedocs.io/en/stable/getting_started/) in your cluster
- [Prometheus in your cluster](https://devopscube.com/setup-prometheus-monitoring-on-kubernetes/) (running as service and [kube state metrics](https://devopscube.com/setup-kube-state-metrics/) enabled)
- [A Fiberplane account](https://studio.fiberplane.com/) 
- [Fiberplane's CLI client fp](https://docs.fiberplane.com/docs/cli)

## Fiberplane template
1. Open your shell and naviagte to the folder where you like to store the template
2. Initiate the template: ```
fp template init --template-path ./argocd-template.jsonnet```
3. Create a new template in studio: ```fp template create --fp template create argocd-template.jsonnet --template-name argocd ```
4. Select the workspace and provide a description
5. Select yes to create a Trigger (Webhook URL) for the template
6. © Save the trigger url, looking something like this ``` Trigger URL:  https://studio.fiberplane.com/api/triggers/xxxxxxxxxxxxxxx/xxxxxxxxxxxxxxxxxxxxxxxxxxx ```

Note: We will update the template content later. For now we just need the endpoint in order to create the argocd-notification webhook

## Argocd-notification
In order to create the webhook we need to modify the **argocd-notification-cm.yaml**. 

### Webhook

```yaml
data:
  service.webhook.fiberplane: |
    url: https://studio.fiberplane.com/api/triggers/xxxxxxxxxxxxxxxxxxxxxxxxxx
    headers:
    - name: Content-Type
      value: application/json
```

℗ *Paste here the trigger url from the step generate before*

### Argocd-notification templates

Next, we need to define a argocd-notifaction template in the same yaml file: 

```yaml
data:
  template.app-sync-failed: |
    webhook:
      fiberplane:
        method: POST
        body: |
          {
            "status": "{{.app.status.sync.status}}",
            "name": "{{.app.metadata.name}}",
            "url": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true",
            "errormessage": "{{.app.status.operationState.message | replace "\"" "\\\""}}",
            "operationState": "{{.app.status.operationState.finishedAt}}",
            "repo":"{{.app.spec.source.repoURL}}"
          }

```

In the body you can define which information you like to pass to the notebook. 

💡 In this tutorial we use the app-sync-failed trigger. You can define templates for multiple triggers as well as define your own triggers. 

✏️ You can find the full argocd-notification-cm.yaml in this repo. Argocd-notifaction-cm comes already with usefule templates and triggers including integration possibilities out of the box for mail and slack. 

## Fpd and Prometheus
In order to also include some metrics from Prometheus in the notebook we need to use Fiberplane's Daemon (fpd) to connect the running Prometheus in our cluster: 

1. Create a namespace for the fiberplane daemon
2. Generate a Fiberplane fpd Token either via the [fiberplane studio UI](https://docs.fiberplane.com/docs/deploy-to-kubernetes#generate-an-fpd-api-token-in-the-studio) or using the [CLI fp](https://docs.fiberplane.com/docs/quickstart#generate-a-daemon-api-token-using-the-cli).
3. Apply the configmap.yaml and apply the deployment.yaml as described in the [docs](https://docs.fiberplane.com/docs/deploy-to-kubernetes). Make sure to link your prometheus instance. If prometheus runs as a service in the same cluster under a different namespace you can use the follwing patter: ``` url: http://servicename.namespace.svc.cluster.local ```
4. Make sure your cluster has access to the interent
5. Check logs and fiberplane studio to see if the data integration is successful 

✏️ You can find the configmap.yaml and deployment yaml [here](https://github.com/fiberplane/quickstart/tree/main/proxy-kubernetes). 


## Update Fiberplane template and content
Open the template in a text editor. We can now include the information we get from the argocd-notification webhook with the POST call as well as metrics from Prometheus that we connected via fpd. 

### Using data from the webhook

```yaml
# Access the REST body and save the value to variables
function(
  title= 'argocd',
  status='',
  name='',
  url='',
  operationState='',
  repo ='',
  errormessage = ''
)

#Use the variables to create lables for your notebook
fp.notebook
.addLabels({
    'service': name,
    'status': status 
    })

# Use it in a text cell
fp.notebook
.addCells([
    c.text('The sync operation of application ' + name + ' has failed at ' + operationState),

])

```


### Using data from your provider

```yaml
# Set your provider to the notebook
fp.notebook
  .setDataSourceForProviderType('prometheus', 'data-source-name', 'proxy-name')

# Use queries to the provider to include as cells in your notebook

fp.notebook
  .addCells([
    .c.provider(
      title='',
      intent='prometheus,timeseries',
      queryData='application/x-www-form-urlencoded,query=min_over_time%28sum+by+%28namespace%2C+pod%29+%28kube_pod_status_phase%7Bphase%3D%7E%22Pending%7CUnknown%7CFailed%22%7D%29%5B15m%3A1m%5D%29+%3E+0',
     )
  ])

```
✏️ You can find the full template in this repo. 

### Updating your template in fiberplane studio

* First you can use the CLI to validate your template: ``` fp templates validate argocd.jsonnet ``` 
* Update your template with the CLI ``` fp templates update --template-path ```


## Add Github repo to argocd and subscripe to webhook
Finally let's tell argo which repo to poll and subscribe the app to a trigger and the webhook. Open your terminal:

```
kubectl apply -n argocd -f - << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: YOUR_APPLICATION_NAME
  annotations:
    notifications.argoproj.io/subscribe.on-sync-failed.fiberplane: ""
spec:
  destination:
    namespace: default
    server: https://kubernetes.default.svc
  project: default
  source:
    path: PATH_IN_YOUR_REPO
    repoURL: https://github.com/YOUR_REPO
    targetRevision: HEAD
  syncPolicy:
    automated: {}
EOF

```

