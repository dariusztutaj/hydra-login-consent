# Remove dependency to dex, apiserver-proxy and iam-kubeconfig service from cluster-user tests POC

## Overview

In Kyma 1.x we use dex, apiserver-proxy and iam-kubeconfig to provide support for OIDC-based user authentication.  
Dex is issuing tokens and apiserver-proxy is the primary "consumer" of api requests authenticated with Dex-issued tokens.  
Apiserver-proxy verifies the tokens and then forwards the requests to the real K8s API server, using it's almost-admin Service Account.  
In this way we avoid troubles of configuring K8s API server with OIDC parameters like trusted issuer and related SSL/TLS certificate trust issues, especially with self-signed certificates.  
In Kyma 2.0 we want to get rid of Dex, Apiserver-proxy and Iam-kubeconfig service.

## The plan
In Kyma 2.0 we have to face the challenges with configuring K8s API Server with OIDC settings, so that the API Server itself will verify the OIDC tokens and extract subject/group information from these tokens.  
There are three challenges here:  
1) Finding an easy to integrate OIDC provider to use with `cluster-user-tests`
2) Configuring K8s API sever to trust the OIDC provider we've chosen
3) Configuring K8s API server to be able to fetch OIDC keys from the provider endpoint using SSL protocol. This might be a problem when we use a self-signed certificate to expose the provider, which is likely to be the case during testing.

This project, and this document is created to solve problem 1.  
Other two problems remain to be fixed.

## The solution

Finding OIDC provider to use is simple: we already have it. It's ORY/Hydra server. We only have to configure it so that we have:
- a set of static users for testing purpose
- ability to embed custom claims in issued OIDC tokens

### The details
Hydra is certified OIDC provider. But Hydra is **not** an Identity provider. It means Hydra doesn't have any user database. You can't configure Hydra with static users either. You have to *integrate* Hydra with some external user-database to have such features.  
Hydra offers well-defined *extension points* that allow you to integrate external *ID provider* with OIDC flows.  
Fortunately, ORY provides a sample/demo application that serves as an example of how one can implement the *extension points*.  

This project contains a version of this sample application with small changes necessary to implement our scenario.  
The application is written in Typescript, and the changes are really, really small.  
Take a look at the commit history: the first commit contains the ORY codebase from version: `v1.10.3`, the next commits are my changes.  
I've introduced static users along with passwords and group mapping.  
Code for configuring custom claims in OIDC token is also present, take a look how `email` claim is added (`src/routes/consent.ts`)

## Installation steps

Assumption: Kyma 2.x is installed along with ORY component
Expected result: Hydra-login-consent-app is installed and integrated with Hydra. OIDC flow for static users is possible, proper token in JWT format with expected claims can be acquired using a web browser. All requests are using public Kyma domain name and the Kyma TLS certificate.

1) Configure access to your cluster. Set current directory to **this** project root.
2) Prepare the resources.
    In the k8s subfolder, edit `VirtualService.yaml`, replacing domain name in `host` attribute with the domain name of your cluster.
3) Apply the resources.
    ```
    % kubectl create -f k8s
    oauth2client.hydra.ory.sh/testclient3 created
    deployment.apps/ory-hydra-login-consent created
   service/ory-hydra-login-consent created
   virtualservice.networking.istio.io/ory-hydra-login-consent created
   ```

4) Ensure the Deployment is running and Oauth2Client is registered

   The Deployment:
   
       % kubectl -n kyma-system get pods -l app=ory-hydra-login-consent
       NAME                                       READY       STATUS      RESTARTS           AGE
       ory-hydra-login-consent-676f9c854b-5b6rf   2/2         Running     0                  4m46
      
  
   Generated client_id (necessary in the further steps!):
   
    
       % kubectl -n kyma-system get secret testclient3 -o jsonpath='{.data.client_id}' | base64 -D
       22a0d842-a62f-4fe4-8a28-99ed893784e7

5) Configure Hydra to use deployed OIDC extension points

    Edit the `ory-hydra` deployment:
    
       kubectl -n kyma-system edit deployment ory-hydra

    Replace or add the following environment variables into your Hydra Deployment - **remember to change the domain name!**
    The LOG_LEAK_SENSITIVE_VALUES is not necessary, it increases Hydra error logging verbosity
    
       - name: LOG_LEAK_SENSITIVE_VALUES
         value: "true"
       - name: URLS_LOGIN
         value: https://ory-hydra-login-consent.piotr-cstr-usrs.goatz.shoot.canary.k8s-hana.ondemand.com/login
       - name: URLS_CONSENT
         value: https://ory-hydra-login-consent.piotr-cstr-usrs.goatz.shoot.canary.k8s-hana.ondemand.com/consent
       - name: URLS_SELF_ISSUER
         value: https://oauth2.piotr-cstr-usrs.goatz.shoot.canary.k8s-hana.ondemand.com/
       - name: URLS_SELF_PUBLIC
         value: https://oauth2.piotr-cstr-usrs.goatz.shoot.canary.k8s-hana.ondemand.com/


6) Prepare OIDC request

    Replace values for:
      - domain name
      - client_id (you should have this value in step 4.)

    You can also change the `state` and `nonce` if you wish, the only requirement for these values is that they should be "random", have high entropy.

       https://oauth2.piotr-cstr-usrs.goatz.shoot.canary.k8s-hana.ondemand.com/oauth2/auth?client_id=22a0d842-a62f-4fe4-8a28-99ed893784e7&response_type=id_token&scope=openid&redirect_uri=http://testclient3.example.com&state=dd3557bfb07ee1858f0ac8abc4a46aef&nonce=lubiesecurityskany

7) Paste the URL in the browser. 
    - Login using credentials found in `src/routes/login.ts`, function: `authenticate`
    - On consent screen select `openid` and confirm with `Allow access`
    - It might take a few seconds, be patient...
    - On success you are redirected to `http://testclient3.example.com/#id_token=eyJhbG...` It's a non-existing URL - don't worry, we don't need it really.
    - Copy the id_token value
    - You can decode the value using `https://jwt.io/` to ensure all necessary fields have proper values.
  
