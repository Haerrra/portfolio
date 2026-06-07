## Airflow
### 환경
- [MWAA AWS 콘솔](https://<acme-mwaa-endpoint>/home)
- airflow 2.10.3
- python 3.11.7
### 데이터소스
- 데이터브릭스
  - acme-analysis-ws
- 빅쿼리
  - 보안이슈로 연동 불가

---

## Github Repo
### Git 브랜치 전략
- Git Flow 를 따른다
  - main 브랜치가 배포된다
  - feature 브랜치에서 개발한다
  - dev 브랜치는 사용하지 않는다
### 폴더 구조
```
airflow-data-analysis
└───dags
│   └───pxa            # airflow 에 동기화되는 폴더
│   ...
```
### Github Repo <-> Airflow 동기화 과정
- 사용자가 파일을 변경하여 main 브랜치에 push 한다
- dags/DA/ 내 파일이나 폴더의 변경이 생기면
  - airflow 와 동기화된다
- dags/DA/ 외 파일이나 폴더의 변경이 생기면
  - airflow 와 동기화하지 않는다

---

## prerequisite
### install poetry
```shell
curl -sSL https://install.python-poetry.org | python3 -
# pipx install poetry
poetry --version
```
### install pyenv
```shell
brew install pyenv
```
shell setting: [link](https://github.com/pyenv/pyenv?tab=readme-ov-file#b-set-up-your-shell-environment-for-pyenv)
### create virtual environment
```shell
pyenv install 3.11.7
pyenv local 3.11.7  # Activate Python 3.11.7 for the current project
```
- 새로운 터미널을 열거나 `source ~/.zshrc` 혹은 `source ~/.bashrc` 명령어로 pyenv 설정 적용
- `pyenv version` 로 파이썬 버전이 3.11.7 로 변경되었는지 확인
```shell
poetry install
```
