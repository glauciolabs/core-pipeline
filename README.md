# core-pipeline

Workflow reutilizavel de GitHub Actions para build, tagging e entrega GitOps.

## O que este repositorio entrega

- build de containers
- tagging no formato `<versao>-<sha-curto>-<environment>`
- scans de seguranca com Snyk
- integracao com Argo CD

## Modos de entrega com Argo CD

### `argocd_delivery_mode: declarative`

Modo recomendado.

- o workflow publica artefatos e tags
- nao altera `Application` ou `AppProject` no cluster via CLI
- quando `gitops_repo_url` e informado, a promocao acontece por commit no repositorio GitOps de ambiente
- quando `gitops_repo_url` nao e informado, a pipeline apenas valida e deixa a promocao para outro fluxo Git

### `argocd_delivery_mode: self-service`

Modo de compatibilidade e bootstrap.

- ainda usa CLI do Argo CD para reconciliar app/projeto
- deve ser tratado como excecao operacional

## Guardrails atuais

- a CLI do Argo CD fica fixada em uma versao conhecida por padrao
- o sync padrao usa `argocd_sync_strategy: safe`
- `replace-force` fica disponivel apenas para excecoes controladas
- tags existentes nao sao recriadas

## Referencias

- [pipelines.md](/home/gcampos/git/core-pipeline/docs/pipelines.md)
- [pipeline-variables.md](/home/gcampos/git/core-pipeline/docs/pipeline-variables.md)
- [GITOPS-ARGOCD-STRATEGY.md](/home/gcampos/git/docs/GITOPS-ARGOCD-STRATEGY.md)
