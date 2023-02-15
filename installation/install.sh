command to install Tekton Pipeline in kubernetes cluster
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

The CLI is not updated to use latest pipeline release, because of which there is an error when executing tasks using tkn. 
As a workaround i have switched back to older pipeline version. The issue is being tracked under https://github.com/tektoncd/cli/issues/1837
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.42.0/release.yaml


