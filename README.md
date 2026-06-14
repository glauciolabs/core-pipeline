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
- nao altera `Application` ou `AppProject` via CLI
- a promocao acontece no repositorio GitOps de ambiente

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
