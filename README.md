<h3 align="center"><b>Fragata Host</b></h3>
<p align="center"><b>Plataforma de virtualização open source, baseada no hipervisor Xen</b></p>

Fragata Host é um hard fork do XCP-ng, iniciado em 29 de outubro de 2026 a partir do commit `5282a6b` do repositório `xcp-ng/xcp`. A partir desse ponto o projeto segue roadmap, versionamento e identidade próprios.

Este repositório é o ponto de entrada do projeto: issues, documentação de processo, scripts de build e listas de pacotes das ISOs. O código do sistema instalado (release, instalador, geração de ISO, console de texto) vive em repositórios próprios, listados abaixo.

## Componentes

| Produto | Papel | Origem |
|---|---|---|
| **Fragata Host** | hipervisor e host de virtualização | XCP-ng |
| **Fragata** | orquestração, backup e API para um ou mais pools | Xen Orchestra |
| **Fragata Deck** | interface leve embutida no host | XO Lite |

## Repositórios

- `fragata-host` (este): entrada, scripts, listas de ISO.
- `fragata-orchestrator`: orquestrador, backup, API REST, interfaces web.
- A forkar quando o build do Host começar: `xcp-ng-release`, `host-installer`, `create-install-image`, `xsconsole`, `xcp-ng-build-env`.

## Estado

Pré-1.0. A ISO do Fragata Host é gerada por `scripts/fragata-iso/build-iso.sh` a partir da ISO do XCP-ng da mesma versão: o host instalado se identifica como `Fragata Host`, com os pacotes, o canal de atualização e as chaves do upstream. O console de texto, o banner de login e o `os-release` do host instalado ainda vêm dos pacotes do upstream, até o build dos forks. O Fragata gerencia hosts Fragata Host, XCP-ng e XenServer.

## Branches

- `main`: linha de desenvolvimento do Fragata.
- `upstream`: cópia congelada do ponto de origem (`upstream-base`), mantida só para referência e cherry-pick seletivo de correções de segurança. Nunca é mergeada.

## Licença

Mesmas licenças do XCP-ng (GPL-2.0 e licenças por componente). Os avisos de copyright originais são mantidos; consulte `LICENSE`.

## Origem

O XCP-ng é um projeto da Vates e da comunidade XCP-ng. "XCP-ng", "Xen Orchestra" e "XOA" são marcas de seus respectivos donos e não são usadas por este projeto. "Xen" é marca do Xen Project.
