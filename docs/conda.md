install locally miniconda or conda
then use requirements.yml file to create a virtual environment

or

go with local venv solution: to avoid memory consuming conda env

### activate local venv:

`source /home/lightwarrior/venvbox/bookstore/bin/activate`

### in vscode set the python environment : set the path

in `python.defaultInterpreterPath` : File>preferances> settings or ctrl+,
`/home/lightwarrior/venvbox/bookstore/bin/python`

another solution is create the venv folder in project directory and exclude that folder from .gitignore

### whenever want to install packages from requirements.yml

install the dependancy first `pip3 install pyyaml`

python dev-install-packages.py

### github action

1. droplet ip
2. geenerate ssh-keygen
3. note down the passphrase
4. get ssh private key
5. username
   above all for github actions
