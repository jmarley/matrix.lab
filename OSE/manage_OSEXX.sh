################################################################################
for ITEM in nodes pods services ; do echo "## $ITEM"; oc get $ITEM; echo; done
for ITEM in rc dc bc; do echo "## $ITEM"; oc get $ITEM; echo; done
for ITEM in projects templates; do echo "## $ITEM"; oc get $ITEM; done
for ITEM in sa; do echo "## $ITEM"; oc get $ITEM; done
for ITEM in pv pvc; do echo "## $ITEM"; oc get $ITEM; done

# for i in buildconfig deploymentconfig service; do echo $i; oc get $i; echo -e "\n\n"; done
# oc get all
# oc get services
# oc get pods
# oc get rc
# oc get nodes
# oc logs docker-registry-1-deploy

##########################
# Declare PVs/PVCs on Master for Registry
##########################
mkdir -p ~/Projects/default; cd $_
cat << EOF > registry-volume.json
    {
      "apiVersion": "v1",
      "kind": "PersistentVolume",
      "metadata": {
        "name": "registry-storage"
      },
      "spec": {
        "capacity": {
            "storage": "1Gi"
            },
        "accessModes": [ "ReadWriteMany" ],
        "nfs": {
            "path": "/export/nfs/pvs/registryvol",
            "server": "rhel7d.matrix.lab"
        }
      }
    }

EOF
oc create -f registry-volume.json -n default
cat << EOF > registry-volume-claim.json
    {
      "apiVersion": "v1",
      "kind": "PersistentVolumeClaim",
      "metadata": {
        "name": "registry-claim"
      },
      "spec": {
        "accessModes": [ "ReadWriteMany" ],
        "resources": {
          "requests": {
            "storage": "1Gi"
          }
        }
      }
    }

EOF
oc create -f registry-volume-claim.json -n default
oc get pvc

######################### ######################### #########################
# Registry
######################### ######################### #########################
# REGISTRY(S)
oadm registry --create \
    --config=/etc/openshift/master/admin.kubeconfig \
    --credentials=/etc/openshift/master/openshift-registry.kubeconfig \
    --images='registry.access.redhat.com/openshift3/ose-${component}:${version}'

oc volume dc/docker-registry --add --overwrite -t persistentVolumeClaim \
  --claim-name=registry-claim --name=registryvol

######################### ######################### #########################
# Router
#  NOTE:  You need a registry before you can create the router
######################### ######################### #########################
oadm router harouter --stats-password='Passw0rd' --replicas=2 \
  --config=/etc/openshift/master/admin.kubeconfig  \
  --credentials='/etc/openshift/master/openshift-router.kubeconfig' \
  --images='registry.access.redhat.com/openshift3/ose-haproxy-router:v3.0.0.1' \
  --selector='region=infra' --service-account=router

##########################
# Declare PVs/PVCs on Master for *whatever*
##########################
mkdir /root/pvs
export volsize="3Gi"
for volume in pv{1..10} ; do
cat << EOF > /root/pvs/${volume}
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "${volume}"
  },
  "spec": {
    "capacity": {
        "storage": "${volsize}"
    },
    "accessModes": [ "ReadWriteOnce" ],
    "nfs": {
        "path": "/export/nfs/pvs/${volume}",
        "server": "10.10.10.13"
    },
    "persistentVolumeReclaimPolicy": "Recycle"
  }
}
EOF
echo "Created def file for ${volume}";
done
cd /root/pvs
cat pv{1..2} | oc create -f - -n default

######################### ######################### #########################
# SERVICES
######################### ######################### #########################
oadm new-project svcslab --display-name="Services Lab" \
    --description="This is the project we use to learn about services" \
    --admin=oseuser --node-selector='region=primary'

######################### ######################### ######################### 
# PROJECTS
######################### ######################### ######################### 
oadm new-project resourcemanagement --display-name="Resources Management" \
    --description="resource management project" \
    --admin=oseuser --node-selector='region=primary'
oc policy add-role-to-user admin oseuser -n resourcemanagement

# QUOTAS
cat << EOF > quota.json
{
  "apiVersion": "v1",
  "kind": "ResourceQuota",
  "metadata": {
    "name": "test-quota"
  },
  "spec": {
    "hard": {
      "memory": "1Gi",
      "cpu": "20",
      "pods": "3",
      "services": "5",
      "replicationcontrollers":"5",
      "resourcequotas":"1"
    }
  }
}
EOF
oc create -f quota.json --namespace=resourcemanagement

# LIMITS
cat << EOF > limits.json
{
    "kind": "LimitRange",
    "apiVersion": "v1",
    "metadata": {
        "name": "limits",
        "creationTimestamp": null
    },
    "spec": {
        "limits": [
            {
                "type": "Pod",
                "max": {
                    "cpu": "500m",
                    "memory": "750Mi"
                },
                "min": {
                    "cpu": "10m",
                    "memory": "5Mi"
                }
            },
            {
                "type": "Container",
                "max": {
                    "cpu": "500m",
                    "memory": "750Mi"
                },
                "min": {
                    "cpu": "10m",
                    "memory": "5Mi"
                },
                "default": {
                    "cpu": "100m",
                    "memory": "100Mi"
                }
            }
        ]
    }
}
EOF
oc create -f limits.json --namespace=resourcemanagement

# DISPLAY SETTINGS
oc get quota -n resourcemanagement 
oc describe quota test-quota -n resourcemanagement
oc describe limitranges limits -n resourcemanagement

su - oseuser 
oc login -u oseuser --insecure-skip-tls-verify --server=https://rh7osemst01.matrix.lab:8443
oc project resourcemanagement
mkdir -p ~/proeject/resourcemanagement/; cd $_

cat <<EOF > hello-pod.json
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "hello-openshift",
    "creationTimestamp": null,
    "labels": {
      "name": "hello-openshift"
    }
  },
  "spec": {
    "containers": [
      {
        "name": "hello-openshift",
        "image": "openshift/hello-openshift:v0.4.3",
        "ports": [
          {
            "containerPort": 8080,
            "protocol": "TCP"
          }
        ],
        "resources": {
          "limits": {
            "cpu": "10m",
            "memory": "16Mi"
          }
        },
        "terminationMessagePath": "/dev/termination-log",
        "imagePullPolicy": "IfNotPresent",
        "capabilities": {},
        "securityContext": {
          "capabilities": {},
          "privileged": false
        },
        "nodeSelector": {
          "region": "primary"
        }
      }
    ],
    "restartPolicy": "Always",
    "dnsPolicy": "ClusterFirst",
    "serviceAccount": ""
  },
  "status": {}
}
EOF
oc create -f hello-pod.json -n resourcemanagement

######################
# PROJECT (S2I Build)
######################
# On Master
#  Simple Sinatra using source
MYPROJ='hello-s2i'
oadm new-project ${MYPROJ} --display-name="Hello Source2Image" \
    --description="This project is for Source to Image builds" \
      --node-selector='region=primary' --admin=oseuser
# Since I have now "plumbed my ENV to AD"....
oc policy add-role-to-user admin 'CN=OSE User,CN=Users,DC=matrix,DC=lab' -n hello-s2i

su - oseuser
oc login -u oseuser -p Passw0rd --insecure-skip-tls-verify --server=https://rh7osemst01.matrix.lab:8443
MYPROJ='hello-s2i'
mkdir -p ~/Projects/${MYPROJ}; cd $_
oc project ${MYPROJ} 
oc new-app https://github.com/openshift/simple-openshift-sinatra-STI.git -o json | tee ./simple-sinatra.json
oc create -f ./simple-sinatra.json -n ${MYPROJ}
oc build-logs `oc get builds | grep sinatra | awk '{ print $1 }'`

curl http://`oc get services | grep sinatra | awk '{ print $2":"$4 }' | cut -f1 -d\/`

oc expose service simple-openshift-sinatra \
  --hostname=mysinatra.cloudapps.matrix.lab
# oc edit route

###################################
#  Simple Sinatra using my update 
cd ~/projects/simple-sinatra
git clone https://github.com/jradtke-rh/simple-openshift-sinatra-sti.git
MYLINE=`grep -n get simple-openshift-sinatra-sti/app.rb | awk -F: '{ print $1 }'`
MYLINE=$((MYLINE+2))
sed -i -e "${MYLINE}i\ \ \"Improved\!\" " simple-openshift-sinatra-sti/app.rb
cd simple-openshift-sinatra-sti
git config --global user.email "jradtke@redhat.com"; git config --global user.name "James Radtke"
git commit -m "updating app.rb" app.rb
git push
cd - 

oc new-app https://github.com/jradtke-rh/simple-openshift-sinatra-STI.git -o json | tee ./simple-sinatra.json
oc create -f ./simple-sinatra.json -n hello-s2i
while true; do oc get builds | grep Running; sleep 2; done
oc build-logs <build-name>
curl `oc get services | grep sinatra | awk '{ print $2":"$4 }' | cut -f1 -d\/`

oc expose service simple-openshift-sinatra \
  --hostname=mysinatra.cloudapps.matrix.lab
oc edit route

######################
# PROJECT (Binary Deployment) -- This is pretty hosed... :-(
######################
# PRE
# fork https://github.com/JaredBurck/ose-team-ex-3 to https://github.com/jradtke-rh/ose-team-ex-3
# clone the repo
# add a Dockerfile 
oc new-project petstore
oc policy add-role-to-user admin oseuser -n petstore 
su - oseuser
oc login -u oseuser --insecure-skip-tls-verify --server=https://rh7osemst01.matrix.lab:8443
oc project petstore 
mkdir -p projects/petstore && cd $_
#git clone https://github.com/jboss-developer/ticket-monster/
git clone http://github.com/jradtke-rh/petstore.git
cd petstore
cat << EOF > ./Dockerfile
FROM registry.access.redhat.com/jboss-eap-6/eap-openshift:6.4
EXPOSE 8080 8888
RUN curl https://github.com/jradtke-rh/ose-team-ex-3/blob/master/deployments/jboss-helloworld.war -o \$JBOSS_HOME/standalone/deployments/ROOT.war
#RUN curl https://github.com/jradtke-rh/ose-team-ex-3/blob/master/deployments/ticket-monster.war -o \$JBOSS_HOME/standalone/deployments/ROOT.war
EOF
git commit -m "Adding Dockerfile" Dockerfile && git push
cd -
oc new-app https://github.com/jradtke-rh/petstore.git --name=petstore
curl `oc get services | grep petstore | awk '{ print $2":"$4 }' | cut -f1 -d\/`
oc expose service petstore --hostname=petstore.cloudapps.matrix.lab
oc exec -it -p petstore-1-build /bin/bash # This doesn't work since it is a privileged container, or something...


######################
# Registry (Securing)
######################
REGIP=`oc get service docker-registry | grep docker-registry | awk '{ print $2 }'`
CERTPATH=/etc/openshift/master/
oadm ca create-server-cert --signer-cert=${CERTPATH}ca.crt \
  --signer-key=${CERTPATH}ca.key --signer-serial=${CERTPATH}ca.serial.txt \
  --hostnames='docker-registry.default.svc.cluster.local,${REGIP}' \
  --cert=${CERTPATH}registry.crt --key=${CERTPATH}registry.key
oc secrets new registry-secret ${CERTPATH}registry.crt ${CERTPATH}registry.key
oc secrets add serviceaccounts/default secrets/registry-secret
oc volume dc/docker-registry --add --type=secret \
    --secret-name=registry-secret -m /etc/secrets
oc env dc/docker-registry \
    REGISTRY_HTTP_TLS_CERTIFICATE=/etc/secrets/registry.crt \
    REGISTRY_HTTP_TLS_KEY=/etc/secrets/registry.key
POD=`oc get pods | grep ^docker-registry | awk '{ print $1 }'`
oc -it -p $POD exec ls /etc/secrets # this doesn't work for some reason....


######################
# GIT Quicky
######################
echo "# matrix.lab" >> README.md
git init
git add README.md
git commit -m "first commit"
git remote add origin https://github.com/jradtke-rh/matrix.lab.git
git push -u origin master

