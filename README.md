# kafka-tls-sasl-acl-example

### Requirements

minikube (https://minikube.sigs.k8s.io/docs/start/)  
kubectl (https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)  
helm (https://helm.sh/docs/intro/install/)  
openssl   
keytool 

### Setup environment

```
# start minikube with k8s version 1.27
minikube start --kubernetes-version=v1.27.0

# check minikube status
minikube status

# check k8s connection status
kubectl get nodes

# Clone example repo
git clone https://github.com/abalalaev/kafka-tls-sasl-acl-example.git
cd ./kafka-tls-sasl-acl-example
```

### Generate certificates

For this example we will use self-signed sertificates created by openssl. 

```
# This shell script will generate a CA certificate and a certificate for the Kafka server/client signed by this CA
./generate-certs.sh
```

### Create truststore and keystore jks files

The keystore stores each machine’s own identity. The truststore stores all the certificates that the machine should trust. In this example all kafka brokers and clients will share the same keystore and truststore files.

```
# Create kafka.truststore.jks containing previously created root.ca certificate. Jks will be protected by password "jkspassword".
keytool -importcert -noprompt -storetype jks -alias root.ca -keystore kafka.truststore.jks -file certs/root.ca.crt -storepass jkspassword

# Create pkcs12 containing previously created example.com certificate and private key. pkcs12 will be protected by password "keypassword".
openssl pkcs12 -export -in certs/example.com.crt -inkey certs/example.com.key -name example.com -out keystore.p12 -passout pass:keypassword

# Create kafka.keystore.jks by importing created pkcs12 file. Jks will be protected by password "jkspassword".
keytool -importkeystore -srckeystore keystore.p12 -srcstoretype pkcs12 -srcstorepass keypassword -srcalias example.com -destkeystore kafka.keystore.jks -deststoretype pkcs12 -deststorepass jkspassword -destalias example.com 
```

### Create k8s secret containing created truststore and keystore

```
kubectl create secret generic kafka-jks --from-file=kafka.truststore.jks=./kafka.truststore.jks --from-file=kafka.keystore.jks=./kafka.keystore.jks
```

### Deploy kafka

```
# Deploy bitnami kafka helm chart using kafka-values.yml
helm install kafka oci://registry-1.docker.io/bitnamicharts/kafka --values kafka-values.yml --namespace default

# Check kafka's pods status
kubectl get pods -n default
```

### Try to use kafka client with tls and acl

```
# Create kafka client pod
kubectl run kafka-client --restart='Never' --image docker.io/bitnami/kafka:3.6.1-debian-12-r12 --namespace default --command -- sleep infinity

# Copy truststore and keystore jks files to the kafka-client pod's fs
kubectl cp kafka.truststore.jks kafka-client:/bitnami/kafka/config/kafka.truststore.jks --namespace default
kubectl cp kafka.keystore.jks kafka-client:/bitnami/kafka/config/kafka.keystore.jks --namespace default

# Copy kafka Admin client.properties file to the kafka-client pod's fs
kubectl cp kafkaAdmin.client.properties kafka-client:/tmp/client.properties --namespace default

# Login to the kafka-client pod
kubectl exec --tty -i kafka-client --namespace default -- bash

# Create two test topics (test1 and test2)
kafka-topics.sh --command-config /tmp/client.properties --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092 --topic test1 --create

kafka-topics.sh --command-config /tmp/client.properties --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092 --topic test2 --create

# Produce some test messages to the both test topics
kafka-console-producer.sh --producer.config /tmp/client.properties --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092 --topic test1

kafka-console-producer.sh --producer.config /tmp/client.properties --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092 --topic test2

# Provide read permisson for test1 topic to kafkaUser principal 
kafka-acls.sh --command-config /tmp/client.properties --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092 --add --allow-principal "User:kafkaUser" --operation Read --group '*' --topic test1

# Logout and copy kafka User client.properties file to the kafka-client pod's fs
kubectl cp kafkaUser.client.properties kafka-client:/tmp/client.properties --namespace default

# Login to the kafka-client pod
kubectl exec --tty -i kafka-client --namespace default -- bash

# Try to consume test1 topic as kafkaUser principal (this should work)
kafka-console-consumer.sh --consumer.config /tmp/client.properties --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092 --topic test1 --from-beginning

# Try to consume test2 topic as kafkaUser principal (this should not work because of 'Topic authorization failed')
kafka-console-consumer.sh --consumer.config /tmp/client.properties --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092 --topic test2 --from-beginning
```

