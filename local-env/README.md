# Ory Hydra as OIDC provider - local setup

1. Provision `minikube`:
```
$ kyma provision minikube --vm-driver kvm2 --memory 8500 --cpus 8 
```
2. Install Kyma
```
kyma alpha deploy --components-file ./components.yaml
```
3. Install OauthClient, login consent app, services and virtual services.
```
kubectl apply -f k8s-minikube
```
4. Edit `ory-hydra` deployement and add envs to point to consent endpoints:
```
kubectl -n kyma-system edit deployment ory-hydra
```
```yaml
        - name: LOG_LEAK_SENSITIVE_VALUES
          value: "true"
        - name: URLS_LOGIN
          value: https://ory-hydra-login-consent.kyma.example.com/login
        - name: URLS_CONSENT
          value: https://ory-hydra-login-consent.kyma.example.com/consent
        - name: URLS_SELF_ISSUER
          value: https://oauth2.kyma.example.com/
        - name: URLS_SELF_PUBLIC
          value: https://oauth2.kyma.example.com/
```
5. In another terminal run `minikube tunnel` to create tunnel to `LoadBalancer` type services.

6. Get IP address of ingress gateway used to expose oauth endpoint.
```
IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath="{.status.loadBalancer.ingress[].ip}")
```
7. Add following entries to your local `/etc/hosts` to access oauth endpoint.
```bash
echo ${IP} oauth2.kyma.example.com kyma.example.com ory-hydra-login-consent.kyma.example.com | sudo tee -a /etc/hosts
```

8. Verify you can access oauth endpoint:
```
curl --insecure https://oauth2.kyma.example.com/.well-known/openid-configuration
```
`--insecure` flag is there since you probably don't have ingress' gateway cert in trusted store. The cmd above should return json with oauth endpoint details.

9. Get cert of ingress gateway:
```
kubectl -n istio-system get secrets kyma-gateway-certs -o jsonpath='{.data.tls\.crt}' | base64 -d > ./kyma-cert.crt
```
and move it to minikube folder and restart minikube:
```
mv ./kyma-cert.crt $HOME/.minikube/certs/
minikube start --embed-certs=true
```
after that the certificate can be find in `/usr/share/ca-certificates` and whey trying to access oauth endpoint from minikube does not throw an error.
**Note**: Use the ingress gw IP from step 6.
**Note**: This step is needed in order to `kube-apiserver` be able to resolve issuer dns names.
```
minikube ssh "echo ${IP} oauth2.kyma.example.com kyma.example.com ory-hydra-login-consent.kyma.example.com | sudo tee -a /etc/hosts"
```

10. Redeploy the cluster to use OIDC.

Follow the documentation: https://minikube.sigs.k8s.io/docs/tutorials/openid_connect_auth/
    
- get the oidc client id:
```bash
OIDC_CLIENT_ID=$(kubectl -n kyma-system get secret testclient3 -o jsonpath='{.data.client_id}' | base64 -d)
```
- redeploy minikube:
```bash
minikube start --extra-config=apiserver.authorization-mode=RBAC \
--extra-config=apiserver.oidc-issuer-url=https://oauth2.kyma.example.com/ \
--extra-config=apiserver.oidc-username-claim=email \
--extra-config=apiserver.oidc-client-id=${OIDC_CLIENT_ID} \
--embed-certs=true
😄  minikube v1.22.0 on Fedora 33
🆕  Kubernetes 1.21.2 is now available. If you would like to upgrade, specify: --kubernetes-version=v1.21.2
✨  Using the kvm2 driver based on existing profile
👍  Starting control plane node minikube in cluster minikube
🏃  Updating the running kvm2 "minikube" VM ...
🐳  Preparing Kubernetes v1.16.15 on Docker 20.10.6 ...
    ▪ apiserver.authorization-mode=RBAC
    ▪ apiserver.oidc-issuer-url=https://oauth2.kyma.example.com/
    ▪ apiserver.oidc-username-claim=email
    ▪ apiserver.oidc-client-id=25028367-4bda-4cc8-8d8c-9f0c4bf0d18f
```
**NOTE**: After redeploy coredns tends to fail due to:
```log
pkopec@piorts-nb hydra-login-consent/local-env (master *+) » k logs coredns-5644d7b6d9-275vl 
2021-07-28T09:20:13.179Z [WARNING] plugin/hosts: File does not exist: /etc/coredns/NodeHosts
plugin/hosts: this plugin can only be used once per Server Block
```
to fix this edit coredns config map:

```kubectl -n kube-system edit coredns```

and remove this part in both `Corefile` and `Corefile-backup`:
```
        hosts {
           192.168.39.1 host.minikube.internal
           fallthrough
        }
```

After that you can force coredns pod to restart:
```bash
kubectl -n kube-system delete pod coredns-5644d7b6d9-275vl 
```

### Getting the token
Get the client_id:
```
OIDC_CLIENT_ID=$(kubectl -n kyma-system get secret testclient3 -o jsonpath='{.data.client_id}' | base64 -d)
```
Go to url:
`firefox https://oauth2.kyma.example.com/oauth2/auth?client_id=${OIDC_CLIENT_ID}&response_type=id_token&scope=openid&redirect_uri=http://testclient3.example.com&state=dd3557bfb07ee1858f0ac8abc4a46aef&nonce=lubiesecurityskany`

**TODO:** There is potential problem with jwt expiration if we don't provide refresh token. `response_type=code+id_token` should provide the refresh_token as well as the id_token. Update: this does not work: `unsupported_response_type&error_description=The+authorization+server+does+not+support+obtaining+a+token+using+this+method%0A%0AThe+client+is+not+allowed+to+request+response_type+"code+id_token".&error_hint=The+client+is+not+allowed+to+request+response_type+"code+id_token".&state=dd3557bfb07ee1858f0ac8abc4a46aef`

After login, you get redirect to testclient3, which does not exist, but we need only JWT that is in the redirect URI. Save that for another step.
### Configure kubectl to work with OIDC

```bash
function oidc_curl_jq() {
    curl --insecure https://oauth2.kyma.example.com/.well-known/openid-configuration | jq $1 | tr -d '"'
}
ISSUER_URL=$(oidc_curl_jq ".issuer")
OIDC_CLIENT_ID=$(kubectl -n kyma-system get secret testclient3 -o jsonpath='{.data.client_id}' | base64 -d)
TOKEN="eyJhbGciOiJSUzI1NiIsImtpZCI6InB1YmxpYzo4NDNiNDM0OC1jNjg3LTRjODItOWYxMS04NWY3N2FlZTRlYWIiLCJ0eXAiOiJKV1QifQ.eyJhY3IiOiIwIiwiYXVkIjpbIjc5YjE4YWY1LWVmOGUtNDlmNC1hZGI2LTFmNGEwMzI2ZDM3NyJdLCJhdXRoX3RpbWUiOjE2Mjc0ODYwNDcsImVtYWlsIjoiYWRtaW5Aa3ltYS5jeCIsImV4cCI6MTYyNzQ4OTY1MSwiZ3JvdXBzIjpbImFkbWlucyIsImRldmVsb3BlcnMiLCJ1c2VycyIsImdvYXR6Il0sImlhdCI6MTYyNzQ4NjA1MSwiaXNzIjoiaHR0cHM6Ly9vYXV0aDIua3ltYS5leGFtcGxlLmNvbS8iLCJqdGkiOiI1NjMwZTIxZS05YWQzLTQwOGYtYmNmMC1jNTg3YzQ0MTRjNDAiLCJub25jZSI6Imx1Ymllc2VjdXJpdHlza2FueSIsInJhdCI6MTYyNzQ4NTY3NCwic2lkIjoiMDNhYTdhY2EtYjY0NS00MTllLTk4OGYtYzA4N2JlMGZjNTkxIiwic3ViIjoiYWRtaW5Aa3ltYS5jeCJ9.Xg-Aca-IteYbEQTuvr6WXCz1VhYlhDuJLvLtr13q1j0_GRjBtdglIZwFFnd7NohiMG9tkF1G7RrrtaNv1t_wXzHmp2vEczsS1HvXJUZKSdHHPD2U2yxy7h5nlp-zt9VLtsMckrct2xPwGa-GtsDmiYLBJVNyNaMKr7wBv4agmb1pPIldg9QMOFEkAx4SO9-eN4BpG6k-NmAdeRWbbn6WSFXi_c5nvxkOYcw5EJNAH64cbi75mzvaderjZx0BD8hXnKyn001p8yKriFtFmCUbW6_50w_t8Zaz-dM4JbkTE2_zHvCRD77tTxkqwiKwQYxI0tfTIFl7myyP3MMIF9MW8To-9LL05Rc3YWUu_sbHbtLxEypVkF1Qyz6dxYezf6gH8jacUqtdLqv_l5v4U6SoxLbQfKmArX4yfMhjPkKLmMcCrzaOF7-2k6Y2R31HhshtogftBV6ehtkGmp5Z8PFf_Gr4WGMSQVbGZANuP6hR--ZxD2lwus7VP4j7VYGigmHRuAqTb6AJkN4TP0LQsb8ADpIBwFy1XjXLaApRvoTsbDIJe1W0xiyVS0y037z46lp3jCiCHKM0ikY4xpWHvXgIrAd1Yk-HvECFzuwvQvcC9nYALHM-ZtW1LzySmcggVvR8SfM4J79GWz3TKXtkE7vT5FzkaGWT5XEqaT3vaDQl0Ns"

kctx minikube-oidc

kubectl config set-credentials admin@kyma.cx \
   --auth-provider=oidc \
   --auth-provider-arg=idp-issuer-url=${ISSUER_URL} \
   --auth-provider-arg=client-id=${OIDC_CLIENT_ID} \
   --auth-provider-arg=id-token=${TOKEN}
```

**TODO**: resolve CSRF issues.