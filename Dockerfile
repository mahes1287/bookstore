FROM continuumio/miniconda3:23.3.1-0

RUN mkdir -p /frontend
RUN mkdir -p /backend
RUN mkdir -p /scripts

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install curl -y && \
    curl -sL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs


COPY ./backend/requirements.yml /backend/requirements.yml

COPY ./scripts /scripts
RUN chmod +x /scripts

RUN /opt/conda/bin/conda env create -f /backend/requirements.yml

ENV PATH /opt/conda/envs/bookstore/bin:$PATH
RUN echo "source activate bookstore" >~/.bashrc

WORKDIR /frontend
COPY ./frontend/package.json /frontend/
COPY ./frontend/package-lock.json /frontend/
RUN npm install
COPY ./frontend /frontend
RUN npm run build

COPY ./backend /backend

WORKDIR /backend
