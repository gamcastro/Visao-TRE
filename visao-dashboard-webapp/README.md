# Visão Web/Mobile/TV (Apps Script)

Fonte do painel Web (`?app=web`), Mobile (`?app=mobile`) e Painel TV
(`?app=tv`) da Visão — projeto Apps Script separado do Desktop
(`Visao-TRE`), rodando sobre a mesma planilha de dados.

## Processo de desenvolvimento (2026-09-09, igual ao DICON)

**Dois projetos Apps Script separados, cada um com sua própria
planilha de dados** (nenhum dado de teste toca produção):

| Ambiente | Branch git | Script ID (`.clasp.json`) | Planilha |
|---|---|---|---|
| Homologação | `homolog` (ESTE branch) | `1HeNs2rvTDQipnGXGKpbzFUnk7thYK2a_rBHr2mfkIf5eb883hfwxquc1` | Visão - Homologação (`1NVSQBPx8rtpPv1L9AP4o1a_11WlazjsoFF73tdcgq5M`) |
| Produção | `main` | `1sRfhHjysH5fdCdBNP7PwuZKRNTnULHfBQhtBT5b3sOejq_OTqAg8lvu-` | Visão (produção, `1_2aZhFgplRqCdPVV_lq4XJT9wgqkfbZpEFZRu1Zu9_I`) |

O código é o mesmo nos dois lados, exceto 2 constantes em `Code.gs`
(`AMBIENTE` e `SPREADSHEET_ID`, bem marcadas com comentário) — cada
branch git carrega os valores do seu próprio ambiente, e cada branch
tem seu **próprio `.clasp.json`** (aponta pro script ID certo sozinho
ao trocar de branch com `git checkout`).

**Fluxo, do jeito que o usuário pediu (igual ao processo do DICON)**:
1. Toda mudança é feita e implantada primeiro em **homologação** (branch
   `homolog`, `clasp push && clasp deploy --deploymentId
   AKfycbx7jjcinfP_FkYsXZNNVVoqjUHATWIeS5WqD3XZ7QW0TbM1sIbKmy3wwnj3SdIlRzWbVg`).
2. O usuário testa na URL de homologação e confirma explicitamente
   ("pode implantar em produção").
3. **Só então**: `git checkout main`, merge do `homolog`, ajustar as 2
   constantes (`AMBIENTE`/`SPREADSHEET_ID`) se necessário, `clasp push
   && clasp deploy --deploymentId
   AKfycbzbHfQvOXZ073oYsy4kw-ZYrFVk-WbyRdII9IcV57zxdbetxggFGNsxIE8xs_DGA_o9`.

Nunca implantar direto em produção sem esse passo 2.

## URLs

- Homologação: `https://script.google.com/a/macros/tre-ma.jus.br/s/AKfycbx7jjcinfP_FkYsXZNNVVoqjUHATWIeS5WqD3XZ7QW0TbM1sIbKmy3wwnj3SdIlRzWbVg/exec`
- Produção: `https://script.google.com/a/macros/tre-ma.jus.br/s/AKfycbzbHfQvOXZ073oYsy4kw-ZYrFVk-WbyRdII9IcV57zxdbetxggFGNsxIE8xs_DGA_o9/exec`

## Endpoints de escrita do Desktop (fora desta pasta)

O Visão Desktop grava em 3 outros Web Apps separados (não fazem parte
deste painel Web) — cada um tem cópia de referência com o token em
branco na raiz deste repositório: `apps_script_publicar_inventario.gs`,
`apps_script_atualizar_zonas.gs`, `apps_script_registrar_campanha.gs`.
Cada um já tem uma implantação de HOMOLOGAÇÃO própria (2026-09-09,
apontando pra planilha de homologação) - ver `VisaoPlanilhas.psm1`
($script:AmbienteVisao). As implantações de PRODUÇÃO desses 3 (exceto
Inventário) foram feitas originalmente direto pela UI do Apps Script,
não por `clasp` - promover uma mudança de código pra produção nesses
dois (Campanhas/Zonas) ainda exige colar o código manualmente na UI,
não é um `clasp push` direto como o Inventário/Dashboard.
