# Dissertation Hosted on Azure

This folder holds the Terraform infrastructure for hosting my dissertation project on Azure. The actual application code, full README, architecture diagram, screenshots and cost notes all live in a separate repo:

**[github.com/amaadh2/rpg-map-tracker](https://github.com/amaadh2/rpg-map-tracker)**

## What's in `infra/`

- `main.tf`, `variables.tf`, `outputs.tf`: Resource Group and Storage Account with static website hosting enabled, plus a CDN section that's written but deliberately commented out (explained in the app repo's README)
- `github-oidc.tf`: the Azure AD app registration, service principal, federated identity credential and RBAC role assignment that let GitHub Actions deploy to this storage account without a stored secret

## Why this is split across two repos

The app itself (`rpg-map-tracker`) has its own git history from before this was a portfolio piece, so it stays in its own repo. This folder just holds the Azure side: the infrastructure that hosts it. If you're looking for the live demo, screenshots or the write-up of the architecture decisions, that's all in the app repo linked above.
