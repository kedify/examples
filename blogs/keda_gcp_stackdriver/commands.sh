helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm upgrade -i keda kedacore/keda --namespace keda --create-namespace --version 2.13.1

docker build -t sharadregoti/web-server:v0.1.0 .

#kubectl create secret generic web-server --from-file=service-account.json=./service-account.json
bash load.sh

gcloud container clusters create "default-cluster" --region asia-south1 --machine-type "e2-medium" --disk-type "pd-standard" --disk-size "100" --num-nodes 1

# Add the below flag, to enable worklaod identiy. Replace <project-id> with your id
    --workload-pool=PROJECT_ID.svc.id.goog

# Enabled on cluster
gcloud container clusters update default-cluster --location=asia-south1 --workload-pool=try-out-gcp-features.svc.id.goog

#Enabling on nodepool
gcloud container node-pools update default-pool --cluster=default-cluster --region=asia-south1 --workload-metadata=GKE_METADATA

# Map role to service account
gcloud projects add-iam-policy-binding projects/try-out-gcp-features \
    --role=roles/monitoring.admin \
    --member=principal://iam.googleapis.com/projects/645589419846/locations/global/workloadIdentityPools/try-out-gcp-features.svc.id.goog/subject/ns/default/sa/web-server \
    --condition=None

#
gcloud iam service-accounts create stackdriver-web-server --project=try-out-gcp-features
gcloud projects add-iam-policy-binding try-out-gcp-features --member "serviceAccount:stackdriver-web-server@try-out-gcp-features.iam.gserviceaccount.com" --role "roles/monitoring.admin"
gcloud iam service-accounts add-iam-policy-binding stackdriver-web-server@try-out-gcp-features.iam.gserviceaccount.com --role roles/iam.workloadIdentityUser --member "serviceAccount:try-out-gcp-features.svc.id.goog[default/web-server]"
gcloud iam service-accounts add-iam-policy-binding stackdriver-web-server@try-out-gcp-features.iam.gserviceaccount.com --role roles/iam.workloadIdentityUser --member "serviceAccount:try-out-gcp-features.svc.id.goog[keda/keda-operator]"

kubectl annotate serviceaccount keda-operator --namespace keda iam.gke.io/gcp-service-account=stackdriver-web-server@try-out-gcp-features.iam.gserviceaccount.com

# Get credentials
gcloud container clusters get-credentials default-cluster --location asia-south1

