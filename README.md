# Hands-On Tekton

## Requirements

* [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/)
* [tkn](https://github.com/tektoncd/cli)
* (Optional) [VS Code Tekton extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-tekton-pipelines)


## Installation

First, make sure you've installed [tkn](https://github.com/tektoncd/cli) in your environment, whether you are using Minikube on your local machine or the Kubernetes playground. If you're using the Kubernetes playground, enter commands in the top terminal labeled Terminal Host 1. 

Then, install Tekton pipelines on your cluster.

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```
## Setting up Tekton Dashboard 

First you have to install the latest version of tekton dashboard using Kubectl:
```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml
```
You can monitor the installation :
```bash
kubectl get pods --namespace tekton-pipelines --watch
```
## Accessing Tekton Dashboard
The Tekton Dashboard is not exposed outside the cluster by default, but we can access it by port-forwarding to the tekton-dashboard Service on port 9097.
```bash
http://localhost:9097/
```
![image](https://user-images.githubusercontent.com/34761964/219353770-5aa8d3f8-a7f6-487a-802e-e4cf72e82918.png)


![image](https://user-images.githubusercontent.com/34761964/219353039-a634bd1f-468c-4704-8e60-dd1e9fbfff9a.png)


## Create a Hello World task

Tasks happen inside a pod. You can use tasks to perform various CI/CD operations. Things like compiling your application or running some unit tests.

For this first Task, you will simply use a Red Hat Universal Base Image and echo a hello world.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: hello
spec:
  steps:
    - name: hellofromtekton
      image: openjdk:8-jdk-alpine
      command:
        - /bin/bash
      args: ['-c', 'echo Hello World']
```

Apply this Task to your cluster just like any other Kubernetes object. Then run it using `tkn`, the CLI tool for Tekton.

```bash
kubectl apply -f ./demo/01-hello.yaml
tkn task start --showlog hello
```

## Add a Parameter to the Task

Tasks can also take parameters. This way, you can pass various flags to be used in this Task. These parameters can be instrumental in making your Tasks more generic and reusable across Pipelines.

In this next example, you will create a task that will ask for a person's name and then say Hello to that person.

Starting with the previous example, you can add a `params` property to your task's `spec`. A param takes a name and a type. You can also add a description and a default value for this Task.

For this parameter, the name is `person`, the description is `Name of person to greet`, the default value is `World`, and the type of parameter is a `string`. If you don't provide a parameter to this Task, the greeting will be "Hello World".

You can then access those params by using variable substitution. In this case, change the word "World" in the `args` line to `$(params.person)`.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: hello
spec:
  params:
    - name: person
      description: Name of person to greet
      default: World
      type: string
  steps:
    - name: say-hello
      image: openjdk:11
      command:
        - /bin/bash
      args: ['-c', 'echo Hello $(params.person)']
```

Apply this new Task to your cluster with kubectl and then rerun it. You will now be asked for the name of the person to greet.

You can also specify the parameters directly from the command line by using the -p argument.

```bash
kubectl apply -f ./demo/02-param.yaml
tkn task start --showlog hello
tkn task start --showlog -p person=Joel hello
```

## Multiple steps to Task

Your tasks can have more than one step. In this next example, you will change this Task to use two steps. The first one will write to a file, and the second one will output the content of that file. The steps will run in the order in which they are defined in the `steps` array.

First, start by adding a new step called `write-hello`. In here, you will use the same UBI base image. Instead of using a single command, you can also write a script. You can do this with a `script` parameter, followed by a | and the actual script to run. In this script, start by echoing "Preparing greeting", then echo the "Hello $(params.person)" that you had in the previous example into the ~/hello.txt file. Finally, add a little pause with the sleep command and echo "Done".

For the second step, you can create a new step called `say-hello`. This second step will run in its container but share the /tekton folder from the previous step. In the first step, you created a file in the "~" folder, which maps to "/tekton/home". For this second step, you can use an image `node:14,` and the file you created in the first step will be accessible. You can also run a NodeJS script as long as you specify the executable in the #! line of your script. In this case, you can write a script that will output the content of the ~/hello.txt file.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: hello
spec:
  params:
    - name: person
      description: Name of person to greet
      default: World
      type: string
  steps:
    - name: write-hello
      image: openjdk:11
      script: |
        #!/usr/bin/env bash
        echo Preparing greeting
        echo Hello $(params.person) > /tekton/home/hello.txt
        sleep 2
        echo Done!
    - name: say-hello
      image: node:14
      script: |
        #!/usr/bin/env node
        let fs = require("fs");
        let file = "/tekton/home/hello.txt";
        let fileContent = fs.readFileSync(file).toString();
        console.log(fileContent);
```

You can now apply this Task to your cluster and run this Task with tkn. You will see that you can easily see each step's output as the logs outputs in various colours.

```bash
kubectl apply -f ./demo/03-multistep.yaml
tkn task start --showlog hello
```

## Pipelines

Tasks are useful, but you will usually want to run more than one Task. In fact, tasks should do one single thing so you can reuse them across pipelines or even within a single pipeline. For this next example, you will start by writing a generic task that will echo whatever it receives in the parameters.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: say-something
spec:
  params:
    - name: say-what
      description: What should I say
      default: hello
      type: string
    - name: pause-duration
      description: How long to wait before saying something
      default: "0"
      type: string
  steps:
    - name: say-it
      image: openjdk:11
      command:
        - /bin/bash
      args: ['-c', 'sleep $(params.pause-duration) && echo $(params.say-what)']
```

You are now ready to build your first Pipeline. A pipeline is a series of tasks that can run either in parallel or sequentially. In this Pipeline, you will use the `say-something` tasks twice with different outputs.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: say-things
spec:
  tasks:
    - name: first-task
      params:
        - name: pause-duration
          value: "2"
        - name: say-what
          value: "Hello, this is the first task"
      taskRef:
        name: say-something
    - name: second-task
      params:
        - name: say-what
          value: "And this is the second task"
      taskRef:
        name: say-something
```

You can now apply the Task and this new Pipeline to your cluster and start the Pipeline. Using `tkn pipeline start` will create a `PipelineRun` with a random name. You can also see the logs of the Pipeline by using the `--showlog` parameter.

```bash
kubectl apply -f ./demo/04-tasks.yaml
kubectl apply -f ./demo/05-pipeline.yaml
tkn pipeline start say-things --showlog
```

## Run in parallel or sequentially

You might have noticed that in the last example, the tasks' output came out in the wrong order. That is because Tekton will try to start all the tasks simultaneously so they can run in parallel. If you needed a task to complete before another one, you could use the `runAfter` parameter in the task definition of your Pipeline.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: say-things-in-order
spec:
  tasks:
    - name: first-task
      params:
        - name: pause-duration
          value: "2"
        - name: say-what
          value: "Hello, this is the first task"
      taskRef:
        name: say-something
    - name: second-task
      params:
        - name: say-what
          value: "Happening after task 1, in parallel with task 3"
        - name: pause-duration
          value: "2"
      taskRef:
        name: say-something
      runAfter:
        - first-task
    - name: third-task
      params:
        - name: say-what
          value: "Happening after task 1, in parallel with task 2"
        - name: pause-duration
          value: "1"
      taskRef:
        name: say-something
      runAfter:
        - first-task
    - name: fourth-task
      params:
        - name: say-what
          value: "Happening after task 2 and 3"
      taskRef:
        name: say-something
      runAfter:
        - second-task
        - third-task
```

If you apply this new Pipeline and run it with the Tekton CLI tool, you should see the logs from each Task, and you should see them in order. If you've installed the Tekton VS Code extension by Red Hat, you will also be able to see a preview of your Pipeline and see the order in which each of the steps is happening.

```bash
kubectl apply -f ./demo/06-pipeline-order.yaml
tkn pipeline start say-things-in-order --showlog
```
![image](https://user-images.githubusercontent.com/34761964/219356513-63d9e1ec-1246-4476-b184-f846e79c6c49.png)
![image](https://user-images.githubusercontent.com/34761964/219357276-f1533cb9-bcdb-4191-9281-774dc81d5b03.png)
![image](https://user-images.githubusercontent.com/34761964/219357914-25809ccb-93a2-4d85-a073-29c5fee4b3f0.png)


## Resources

The last object that will be demonstrated in this lab is `PipelineResources`. When you create pipelines, you will want to make them as generic as you can. This way, your pipelines can be reused across various projects. In the previous examples, we used pipelines that didn't do anything interesting. Typically, you will want to have some input on which you will want to perform your tasks. Usually, this would be a git repository. At the end of your Pipeline, you will also typically want some sort of output. Something like an image. This is where PipelineResources will come into play.

In this next example, you will create a pipeline that will take any git repository as a PipelineResource and then count the number of files.

First, you can start by creating a task. This Task will be similar to the ones you've created earlier but will also have an input resource.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: count-files
spec:
  resources:
    inputs:
      - name: repo
        type: git
        targetPath: code
  steps:
    - name: count
      image: openjdk:11
      workingDir: /workspace
      command:
        - /bin/bash
      args: ['-c', 'echo $(find ./code -type f | wc -l) files in repo']
```

Next, you can create a pipeline that will also have an input resource. This Pipeline will have a single task, which will be the `count-files` task you've just defined.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: count
spec:
  resources:
    - name: git-repo
      type: git
  tasks:
    - name: count-task
      taskRef:
        name: count-files
      resources:
        inputs:
          - name: repo
            resource: git-repo
```

Finally, you can create a PipelineResource. This resource is of type `git`, and you can put in the link of a Github repository in the `url` parameter. You can use the repo for this project.

```yaml
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: git-repo
spec:
  type: git
  params:
    - name: url
      value: https://github.com/KamalRajput/Tekton-Basics.git
```

Once you have all the required pieces, you can apply this file to the cluster again, and start this pipelinerun. When you begin the Pipeline with the CLI, you will be prompted on the git resource to use. You can either use the resource you've just created or create your own. You could also use the `--resource` parameter with the CLI to specify which resources to use.

```bash
kubectl apply -f ./demo/07-pipelineresource.yaml
tkn pipeline start count --showlog
tkn pipeline start count --showlog --resource git-repo=git-repo
```

## Workspaces

It is important to note that PipelineResources is still in alpha. The Tekton core team questions whether they should stay in the spec or not. In the latest version of Tekton, `workspaces` were added to share file systems between various tasks in a Pipeline. You can find an example of a pipeline using a workspace in the file workspace.yaml. Workspaces require the usage of PersistentVolumes and PersistentVolumeClaims, which are out of scope for this lab.

```
## More Resources

If you want to keep learning more about Tekton, check out these resources:

* https://tekton.dev - The main tekton website
* https://hub-preview.tekton.dev - Tekton Hub, where you can find reusable tasks and pipelines
* https://developers.redhat.com/topics/ci-cd - Developer-facing info on CI/CD and Tekton
