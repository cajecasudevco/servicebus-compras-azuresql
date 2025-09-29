RG=dockercurso
NS=dockerleo
QUEUE=compras
TOPIC_H=hombretopic
TOPIC_M=mujertopic

# Cola y topics
az servicebus queue create  -g "$RG" --namespace-name "$NS" --name "$QUEUE"
az servicebus topic create  -g "$RG" --namespace-name "$NS" --name "$TOPIC_H"
az servicebus topic create  -g "$RG" --namespace-name "$NS" --name "$TOPIC_M"