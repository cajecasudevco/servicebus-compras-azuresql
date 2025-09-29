API="http://localhost:5081/addcompra"

# 50 hombres en paralelo (20 concurrentes)
seq 50 | xargs -I{} -P 20 sh -c '
  curl -s -X POST "'"$API"'" \
    -H "Content-Type: application/json" \
    -d "{\"Nombre\":\"ClienteHombre{}\",\"Genero\":\"hombre\",\"Monto\":$((RANDOM%9000+1000))}" >/dev/null
'

# 50 mujeres en paralelo (20 concurrentes)
seq 50 | xargs -I{} -P 20 sh -c '
  curl -s -X POST "'"$API"'" \
    -H "Content-Type: application/json" \
    -d "{\"Nombre\":\"ClienteMujer{}\",\"Genero\":\"mujer\",\"Monto\":$((RANDOM%9000+1000))}" >/dev/null
'