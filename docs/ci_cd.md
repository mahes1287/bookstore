# CI / CD Setup

Step-by-step manual how to set up CI / CD with Docker and Gitlab CI.

Contents:

1. Dockerize Django app and PostgreSQL
2. Set up server (e.g. DigitalOcean droplet)
3. Deploy backend to droplet
4. Deploy frontend to droplet

## 1. Dockerize Django app and PostgreSQL

### Ensure Django expects Postgres DB

In `/backend/project/settings.py`

```python
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "HOST": os.environ.get('POSTGRES_HOST'),
        "NAME": os.environ.get('POSTGRES_DB'),
        "USER": os.environ.get('POSTGRES_USER'),
        "PASSWORD": os.environ.get('POSTGRES_PASSWORD'),
        "PORT": os.environ.get('POSTGRES_PORT'),
    }
}
```

### Ensure Django debug mode is only on in dev env

In `/backend/project/settings.py`

```python
DEBUG = os.environ.get('DJANGO_DEBUG', 'True') == 'True'
```

### Set up .env file with DB configurations

In `/envs/dev.env`

```
POSTGRES_PORT=5432
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
POSTGRES_HOST=postgres
POSTGRES_USER=postgres
DJANGO_DEBUG=True
```

### Ensure Postgres Django library is installed

In `/backend/requirements.yml`

```yaml
name: BookstoreBackend
dependencies:
  - ...
  - psycopg2 # <<<<< Add psycopg2 dependency
  - ...
```

### Add Dockerfile

In `Dockerfile`

```dockerfile
FROM continuumio/miniconda3:23.3.1-0

RUN mkdir -p /backend
RUN mkdir -p /scripts

COPY ./backend/requirements.yml /backend/requirements.yml

COPY ./scripts /scripts
RUN chmod +x /scripts

RUN /opt/conda/bin/conda env create -f /backend/requirements.yml

ENV PATH /opt/conda/envs/MotionBackend/bin:$PATH
RUN echo "source activate BookstoreBackend" >~/.bashrc

COPY ./backend /backend

WORKDIR /backend
```

### Add startup script for backend

In `/scripts/dev.sh`

```shell
python manage.py makemigrations
python manage.py migrate
python manage.py runserver 0:8000
```

### Add Docker Compose file

In `docker-compose.yml`, add two services - backend and database. Ensure the backend waits for the database to be ready. Create a persistent Docker volume and declare it. Start development server with shell script and local env variables.

```yaml
version: "3"

services:
  backend:
    image: django:latest
    env_file:
      - ./envs/dev.env
    volumes:
      - ./backend:/backend
    command: "sh /scripts/dev.sh"
    depends_on:
      - postgres

  postgres:
    image: postgres:alpine3.18
    ports:
      - "5555:5432"
    env_file:
      - ./envs/dev.env
    volumes:
      - postgres_db:/var/lib/postgresql/data

volumes:
  postgres_db:
```

### Build image and start dev server

- Build image with `docker build -t bookstore:latest .`
- Start dev server with `docker compose up -d`
- List running containers with `docker ps`
- Inspect running backend container with `docker exec -ti <containerid> bash`
- Shut down dev server with `docker compose down -d`

## 2. Set up server (e.g. DigitalOcean droplet)

### Create a server / droplet

e.g. DigitalOcean: 2 GB Memory / 50 GB Disk / FRA1 - Ubuntu 22.04 (LTS) x64

### SSH into droplet

- Add SSH public key to droplet
- Connect with `ssh root@<ip>`

### Secure droplet

#### Create separate user and add to sudo group

```commandline
sudo adduser <username>
sudo usermod -aG sudo <username>
```

#### Copy private key to new user

```commandline
mkdir -p /home/<username>/.ssh
cp /root/.ssh/authorized_keys /home/<username>/.ssh/authorized_keys
rsync --archive --chown=<username>:<username> ~/.ssh/home/<username>
```

#### Remove SSH root access

```commandline
ssh <username>@<ip>

sudo nano /etc/ssh/sshd_config
```

Modify in `/etc/ssh/sshd_config`

```
...
PermitRootLogin yes <<<--- set to no
...
```

Alternative with SED (streaming editor):

```commandline
sudo sed -i '
    s/#Port 22/Port 22/;
    s/#PubkeyAuthentication yes/PubkeyAuthentication yes/;
    s/PermitRootLogin yes/PermitRootLogin no/
    ' /etc/ssh/sshd_config
```

Restart SSH service with `sudo systemctl restart ssh`

#### Activate firewall

```commandline
sudo ufw enable     # enable firewall
sudo ufw allow 22   # for SSH
sudo ufw allow 80   # for HTTP
sudo ufw allow 443  # for HTTPS
```

Check Firewall status with `sudo ufw status`

Check whether droplet can still be accessed in new terminal tab.

### Install docker on droplet

#### Prevent needrestart

```
# Preventing the needrestart manual prompts for restarting a service during apt-get install.
# This step is unnecessary if using an Ubuntu version older than 22.04
sudo sed -i 's/#\$nrconf{restart} = '\''i'\''/ \
    $nrconf{restart} = '\''a'\''/' \
    /etc/needrestart/needrestart.conf
```

#### Update sources

```
sudo apt-get update
```

#### Install required packages

```
sudo apt-get install \
apt-transport-https \
ca-certificates \
curl \
gnupg2 \
software-properties-common
```

#### Get Docker's GPG key

```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
```

#### Add Docker repository to sources

```
echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
```

#### Update sources and install Docker Community Edition

```
sudo apt-get update
sudo apt-get install docker-ce
```

#### Add current user to docker group

```
sudo usermod -aG docker $USER
newgrp docker
```

#### Test whether Docker and Docker compose are running and accessible

```
docker --version
docker compose version
```

### Set up Gitlab Runner

#### Download and install runner

```
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner
```

#### Register runner

- Log in to Gitlab.com and open repository
- Go to Settings > CI/CD > Runners
- Get registration token
- Register token with `sudo gitlab-runner register`
- Enter details
- Select "shell" as executor

### Add domain to droplet

Add DNS entry to register a new domain / subdomain for project

### Add SSL encryption (using CertBot)

On the droplet:

#### Install snap

```
sudo apt update
sudo apt install snapd
sudo snap install core; sudo snap refresh core
```

#### Install certbot and prepare certificate generation

```
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
```

#### Get a certificate

```
sudo certbot certonly --standalone
```

The certificate will be installed on the webserver (nginx) later

## 3. Deploy backend to droplet

### Prepare Django for production

#### Add gunicorn webserver and flake8 for linting

In `/backend/requirements.yml`:

```yaml
name: MotionBackend
dependencies:
  - ...
  - pip:
      - ...
      - flake8==6.0.0
      - gunicorn==20.1.0
```

#### Add tox.ini with linting rules / exemptions

In `/backend/tox.ini`:

```
[flake8]
exclude = */migrations/,site-packages/,src/,*/migrations/,docs/
max-complexity = 20
max-line-length = 150
statistics = yes
count = yes
```

Ideally, already lint the code locally and correct all errors, before pushing it to the repository:

```commandline
flake8 --exclude='*/migrations/,site-packages/,src/,*/migrations/,docs/' --max-complexity=20 --max-line-length=150 --statistics --count
```

#### Add CSRF and allowed-hosts settings

In `/backend/settings.py`:

```python
...
ALLOWED_HOSTS = ['*']
CSRF_TRUSTED_ORIGINS = ['https://<domain>', 'http://127.0.0.1']
...
```

#### Ensure static/media files settings are correct

In `/backend/settings.py`:

```python
...
STATIC_URL = 'static-files/'
STATIC_ROOT = 'static-files/' if DEBUG else '/static-files/'

USE_X_FORWARDED_HOST = True
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

MEDIA_URL = 'media-files/'
MEDIA_ROOT = 'media-files/' if DEBUG else '/media-files/'
...
```

#### Create shell script for production

In `/scripts/prod.sh`:

```shell
python manage.py collectstatic # Collects the static files
python manage.py migrate # Runs the migrations based on the migration files
gunicorn -w 4 -b 0.0.0.0:8000 project.wsgi:application # starts the gunicorn server on port 8000
```

#### Create .env file for production

In `/envs/prod.env`:

```
POSTGRES_PORT=5432
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
POSTGRES_HOST=postgres
POSTGRES_USER=postgres
DJANGO_DEBUG=False
```

Main difference to dev: Set `DEBUG` in Django to `False`

### Create initial build of image and upload to Gitlab container registry

On local machine:

#### Log in to Gitlab

```
docker login registry.<gitlab_url>
```

#### Build image with registry tags

```
docker build -t registry.<gitlab_url>/<group/s>/<repository> .
```

#### Push image to registry

```
docker push registry.<gitlab_url>/<group/s>/<repository>
```

### Define NGINX server for backend

Create a directory `/nginx` and create an NGINX config file (`default.conf`):
First, define a HTTP server that will redirect all traffic to HTTPS:

```
server {
    # Server for HTTP
    listen 80;
    listen [::]:80;
    server_name amotion-motion.propulsion-learn.ch; # name server with domain
    return 301 https://$server_name$request_uri; # redirect all requests to HTTPS with 301 Permanent
}
```

Then, define a HTTPS server:

```
server {
    # Server for HTTPS
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name amotion-motion.propulsion-learn.ch; # name server with domain
    ssl_certificate /etc/letsencrypt/live/amotion-motion.propulsion-learn.ch/fullchain.pem; # Provide the ssl_certificate
    ssl_certificate_key /etc/letsencrypt/live/amotion-motion.propulsion-learn.ch/privkey.pem; # Provide the ssl_certificate_key

    # SSL Security settings
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    ssl_ecdh_curve secp384r1;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains";
    add_header X-Frame-Options SAMEORIGIN;  # must not be on DENY to make iframe work!
    add_header X-Content-Type-Options nosniff;

    # Directives for /backend/
    location ~ /backend/ {
        add_header 'Access-Control-Allow-Headers' 'Authorization,Content-Type,Accept,Origin,User-Agent,DNT,Cache-Control,X-Mx-ReqToken,Keep-Alive,X-Requested-With,If-Modified-Since,access-control-allow-credentials,Access-Control-Allow-Origin';
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;

        resolver 127.0.0.11;  # docker embedded DNS server
        set $target http://backend:8000;  # point to backend service (as defined in docker-compose.deploy.yml)
        proxy_pass $target; # Proxy traffic to defined target
    }

    # Directives for static-files
    location /static-files/ {
        alias /static-files/;
    }

    # Directices for media-files
    location /media-files/ {
        alias /media-files/;
    }

}
```

### Create a docker-compose file for deployment

In `docker-compose.deploy.yml`:

```yaml
version: "3"

services:
  backend:
    image: registry.<gitlab_url>/<group/s>/<repository>:master
    ports:
      - "8001:8000"
    env_file:
      - ./envs/prod.env
    volumes:
      - static-files:/static-files
      - media-files:/media-files
    command: "sh /scripts/prod.sh"
    depends_on:
      - postgres

  postgres:
    image: postgres:latest
    env_file:
      - ./envs/prod.env
    volumes:
      - postgres_db:/var/lib/postgresql/data

  nginx:
    image: nginx:stable-alpine3.17-slim
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx:/etc/nginx/conf.d
      - static-files:/static-files
      - media-files:/media-files
      - /etc/letsencrypt:/etc/letsencrypt

volumes:
  postgres_db:
  media-files:
  static-files:
```

Main differences to `docker-compose.yml`:

- Instead of taking the local docker image, the latest master image is pulled from the registry
- `prod.env` file is used in backend and postgres service
- Backend service has no volume `/backend` mounted; there is no need to listen for changes on backend files on the prod server.
- `prod.sh` script is executed on startup
- Nginx service is used as a webserver
  - Ports 80 (HTTP) and 443 (HTTPS) are open
  - Static files and media files are mounted from docker volume
  - `nginx` folder from repo is mounted into `/etc/nginx/conf.d`, which is where Nginx looks for `default.conf` files
  - `/etc/letsencrypt` (from droplet) is mounted into `/etc/letsencrypt` of nginx container, so that the SSL certificate files are accessible for Nginx

### Create a docker-compose file for linting

In `docker-compose.ci.yml`:

```yaml
version: "3"
services:
  backend:
    image: "${CI_PIPELINE_ID}:${CI_COMMIT_REF_NAME}"
```

### Create gitlab-ci.yml file with deploy stages

#### Define stages

```yaml
stages:
  - pull
  - build
  - lint
  - push
  - cleanup
  - deploy
```

#### Login to docker before starting pipeline

```yaml
before_script:
  - docker login -u "gitlab-ci-token" -p "$CI_JOB_TOKEN" "$CI_REGISTRY"
```

#### Pull latest image from Gitlab container registry

```yaml
pull:
  stage: pull
  allow_failure: true
  script:
    - docker pull "$CI_REGISTRY_IMAGE":latest
```

#### Build image with tag of current deployment

```yaml
build:
  stage: build
  script:
    - docker build --tag="$CI_PIPELINE_ID":"$CI_COMMIT_REF_NAME" --cache-from="$CI_REGISTRY_IMAGE":latest .
```

#### Lint backend code with flake8

```yaml
lint:
  stage: lint
  script:
    - export CI_PIPELINE_ID=$CI_PIPELINE_ID
    - export CI_COMMIT_REF_NAME=$CI_COMMIT_REF_NAME
    - docker compose -p "$CI_PIPELINE_ID" -f docker-compose.ci.yml run backend flake8 .
```

#### Push build image to container registry both "latest" and, if applicable, "master"

```yaml
push master:
  stage: push
  only:
    - master
  script:
    - docker tag "$CI_PIPELINE_ID":"$CI_COMMIT_REF_NAME" "$CI_REGISTRY_IMAGE":"$CI_COMMIT_REF_NAME"
    - docker push "$CI_REGISTRY_IMAGE":"$CI_COMMIT_REF_NAME"

push latest:
  stage: push
  script:
    - docker tag "$CI_PIPELINE_ID":"$CI_COMMIT_REF_NAME" "$CI_REGISTRY_IMAGE":latest
    - docker push "$CI_REGISTRY_IMAGE":latest
```

#### Clean up old images and containers

```yaml
cleanup:
  stage: cleanup
  when: always
  script:
    - docker rmi -f "$CI_PIPELINE_ID":"$CI_COMMIT_REF_NAME"
    - docker compose -p "$CI_PIPELINE_ID" -f docker-compose.ci.yml down --remove-orphans
```

#### Deploy with `docker-compose.deploy.yml up

```yaml
deploy:
  stage: deploy
  when: manual
  script:
    - docker compose -f docker-compose.deploy.yml pull
    - docker compose -f docker-compose.deploy.yml down --remove-orphans
    - docker volume rm django-docker_build || true
    - docker compose -f docker-compose.deploy.yml up -d
```

### Deploy to Droplet and create Django superuser

- Commit all changes and commit, push, and merge to master branch.
- In Gitlab, go to CI/CD > Pipelines and check whether the pipeline is running
- Start the last step "deploy" with a manual click
- When the deployment succeeded, ssh to Droplet `ssh <username>@<ip>`
- Run `docker ps` to see if all three services (backend, postgres, nginx) are running
- If not, run `docker ps -a` to list all containers
- Run `docker logs <container_id>` to inspect the containers that stopped due to an error
- If all three services are running, check whether the Django admin can be accessed with the browser, via <domain>/backend/admin
- If yes, go on and create a superuser:
  - Run `docker exec -it <backend_container_id> bash`
  - If `pwd` is `/backend`, run `python manage.py createsuperuser`
  - Fill out all details required for a superuser
- Try to log in to the Django admin UI with the superuser credentials

## 4. Deploy frontend to droplet

### Update image with Node installation and React production build

#### Create frontend directory

Add to `Dockerfile`:

```dockerfile
...
RUN mkdir -p /frontend
...
```

#### Install Node.js

Add to `Dockerfile`:

```dockerfile
...
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install curl -y
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs
...
```

#### Build frontend project for production

Add to `Dockerfile`:

```dockerfile
WORKDIR /frontend
COPY ./frontend/package.json /frontend/
COPY ./frontend/package-lock.json /frontend/
RUN npm install
COPY ./frontend /frontend
RUN npm run build
```

First only copying the `package.json` and the `package-lock.json` and then `npm install` will ensure those steps can be cached when there are no changes, and the project does not have to be reinstalled with every code change.

The output of the build will end up in /frontend/dist

### Adjust docker-compose.deploy.yml to use the built frontend

```yaml
...
services:
  backend:
    ...
    volumes:
      - ...
      - build:/frontend/dist
    ...

  ...

  nginx:
    ...
    volumes:
      - ...
      - build:/build

volumes:
  ...
  build:

```

This creates a docker volume "build", which listens to the build output of the `npm run build`. Nginx mounts this into its `/build` folder.

### Extend Nginx config

Inside the HTTPS server configuration, add directives for frontend.
In `/nginx/default.conf`:

```
...

server {

    # Server for HTTPS
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    ...

    location / {
        root /build;
        try_files $uri /index.html;
    }

    ...

}
```

This will ensure that every request to `/ will first go through index.html (which is the entry point of the React app)

### Use .env.local file for API base URL

In `frontend/.env.local`:

```
VITE_API_BASEURL=http://localhost:5173/backend/api
```

Important: Prefix the env variable with `VITE_`, otherwise Vite will not expose it to the application

Create the same for production in `frontend/.env.production`:

```
VITE_API_BASEURL=https://<domain>/backend/api
```

In `/frontend/src/axios/index.js`: Ensure axios is using the env variable

```javascript
export const api = axios.create({
  VITE_API_BASEURL: import.meta.env.VITE_API_BASEURL,
});
```

### Deploy changes to Droplet and perform frontend checks

- Commit all changes and commit, push, and merge to master branch.
- In Gitlab, go to CI/CD > Pipelines and check whether the pipeline is running
- Start the last step "deploy" with a manual click
- When the deployment succeeded, ssh to Droplet `ssh <username>@<ip>`
- Run `docker ps` to see if all three services (backend, postgres, nginx) are running
- If not, run `docker ps -a` to list all containers
- Run `docker logs <container_id>` to inspect the containers that stopped due to an error
- If all three services are running, check whether the frontend can be accessed with the browser, via <domain>/
- If yes, try to log in with the superuser

### Update gitlab-ci pipeline to remove old build volume

In order to ensure the build volume is destroyed before starting the services with the new build, update the `.gitlab-ci.yml`.
First, look up the name of build volume on the droplet:

```
docker volume ls
```

Remember the name of the volume ending with `_build`

Add to `.gitlab-ci.yml`

```yaml
...
deploy:
  ...
  script:
    - ... (docker compose down)
    - docker volume rm <volume_name> || true
    - ... (docker compose up)
```

Ensure the command to remove the docker volume happens between `docker compose ... down` and `docker compose ... up`.

## 5. Set up Dev environment in PyCharm

### Set up Docker and Python interpreter

1. Open PyCharm; go to Settings > Build, Execution, Deployment > Docker
2. Add new instance
3. Configure paths:
   1. Virtual machine path: `/backend`
   2. Local path: `<local path to repo>/backend`
4. Apply
5. As Python interpreter, select conda env from newly created Docker
6. Go to „Edit configurations“
7. Add new configurations for `makemigrations`, `migrate`, `runserver`
   1. Script path: `/backend/manage.py`
   2. Parameters: e.g. `runserver 0:8000`
   3. Python interpreter: Select remote interpreter from docker compose
8. Make and run migrations to ensure database is updated.
9. Start the development server

### Connect to PostgreSQL DB on Docker

1. Open PyCharm, go to Database section (right-side bar)
2. Add new connection and select PostgreSQL
3. Use the following connection: `jdbc:postgresql://localhost:5555/postgres` (based on the port definition on `docker-compose.yml`)
4. Reload the schema; the database tables should now be visible.
