I forked this from https://github.com/speedfl/argocd-reallife-samples/blob/main/organization-multitenancy/chart/ to keep up on my own accord with potential API changes and make my own edits


# team-configuration

## Purpose & usage

A chart to manage AppProject and associated [RBACs](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/).

It deploys:

- ArgoCD `AppProject` with configured RBACs om both `${team}*` and `argocd-${team}` namespaces

It defines 3 roles:

- `admins`: Can perform any action on the provided project.
- `edit`:  Can Get/Sync Application, get logs, run exec in pods and perform any actions on resources deployed by the Application (but not the Application itself).
- `readonly`: Can Get Application and Get logs.

This works with most of the organization / methodologies such as SAfe, Squads...

## Prerequisites

To support this multi-tenancy:

- Authentication must be enabled (example using Azure AD): https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#oidc-configuration-with-dex
- [Application in any namespace](https://argo-cd.readthedocs.io/en/stable/operator-manual/app-any-namespace/) needs to be activated
- If you want your team to use ApplicationSet, [ApplicationSet in any namespace](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Appset-Any-Namespace/) must be activated
- Applications needs to be deployed in namespace `argocd-${id}` (example: `argocd-train-one`)
- Destination namespaces will have to be in format `${id}.*` (example: `train-one-databases`)

## Examples

### Readonly access to all applications

Example of a team who wants to provide readonly access to all apps in this project.

```yaml
id: project-one

sourceRepos:
  - https://github.com/organization/train-one/*
admins:
  project-one-system-team: 00000000-0000-0000-0000-000000000000

readonly:
  project-two:
    glob: '*'
    azureAdId: 11111111-1111-1111-1111-111111111111
  project-three:
    glob: '*'
    azureAdId: 22222222-2222-2222-2222-222222222222
```

### Readonly access on a subset of applications

Example of a team who wants to provide readonly access to subset of apps in this project.

```yaml
id: project-one

sourceRepos:
  - https://github.com/organization/train-one/*
admins:
  project-one-system-team: 00000000-0000-0000-0000-000000000000
readonly:
  customer-one:
    glob: customerone-*
    azureAdId: 33333333-3333-3333-3333-333333333333
```

### Edit access on a subset of applications

Example of a team who wants to provide edit access to subset of apps in this project.

```yaml
id: project-one

sourceRepos:
  - https://github.com/organization/train-one/*
admins:
  project-one-system-team: 00000000-0000-0000-0000-000000000000

edit:
  project-one-agile-team-one:
    glob: 'agile-team-one-*'
    azureAdId: 44444444-4444-4444-4444-444444444444
  project-one-agile-team-two:
    glob: 'agile-team-two-*'
    azureAdId: 55555555-5555-5555-5555-555555555555
```

### Full example with SAfe

In our example we will have:

- A system team that will be full admin. Meaning that they will be able to Create / Update / Delete Application and as well perform all actions on Applications and ApplicationSets
- A Coordination team with System Architect, Product Management and RTE that will be readonly
- A Frontline team for incident management which will be readonly
- 3 Agile Teams. Both will be readonly on the entire project but will be edit on their respective Applications (prefixed by the agile team name)
  - agileone
  - agiletwo
  - agilethree


```yaml
sourceRepos:
  - https://github.com/organization/train-one/*

admins:
  system-team: 00000000-0000-0000-0000-000000000000

readonly:
  coordination:
    glob: '*'
    azureAdId: 11111111-1111-1111-1111-111111111111
  frontline:
    glob: '*'
    azureAdId: 22222222-2222-2222-2222-222222222222
  agileone:
    glob: '*'
    azureAdId: 33333333-3333-3333-3333-333333333333
  agiletwo:
    glob: '*'
    azureAdId: 44444444-4444-4444-4444-444444444444
  agilethree:
    glob: '*'
    azureAdId: 55555555-5555-5555-5555-555555555555

edit:
  agileone:
    glob: 'agileone-*'
    azureAdId: 33333333-3333-3333-3333-333333333333
  agiletwo:
    glob: 'agiletwo-*'
    azureAdId: 44444444-4444-4444-4444-444444444444
  agilethree:
    glob: 'agilethree-*'
    azureAdId: 55555555-5555-5555-5555-555555555555
```

To support multi-tenancy:

- `Application` will have to be prefixed by the team name (example: `agileone-data`)