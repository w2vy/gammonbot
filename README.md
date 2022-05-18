# gammonbot
gammonbot robot to play backgammon against people on fibs.com

# Build and test Docker image

docker build -t w2vy/gammonbot .

docker rm flux_gammonbot
docker run --name flux_gammonbot -p 59898:59898 -e FLUX_PORT=34321 -e VAULT_DNS='127.0.0.1' w2vy/gammonbot

docker push w2vy/gammonbot:latest