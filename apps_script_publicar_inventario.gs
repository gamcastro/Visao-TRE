/*
  Apps Script "Web App" que recebe, via HTTP POST, o resultado de uma
  varredura inteira de uma Zona Eleitoral (do Visão Desktop, ao final de
  cada varredura) e grava/atualiza (upsert por Zona+IP) as linhas
  correspondentes na aba "INVENTARIO" da planilha do Visão - base de
  dados pro futuro Visão Web/Mobile/Painel TV (Trilha B do plano).

  Cria a aba "INVENTARIO" (com cabeçalho) sozinho na primeira chamada,
  se ela ainda não existir - não precisa criar a mão antes.

  Colunas gravadas na aba "INVENTARIO" (nesta ordem):
    A = Zona   B = Sede   C = IP   D = Hostname   E = Tipo   F = Modelo
    G = DetectadoPor   H = Vnc   I = Rc   J = VersaoSis   K = Instalador
    L = UltimaAtualizacao   M = Tecnico

  COMO PUBLICAR (mesmo padrão dos outros apps_script_*.gs deste
  repositório - apps_script_atualizar_zonas.gs/apps_script_receber_cvc.gs):
    1. Acesse https://script.google.com , crie um projeto novo (pode ser
       um projeto separado dos outros - não precisa ser o mesmo).
    2. Apague o conteúdo padrão de "Code.gs" e cole este arquivo inteiro.
    3. Troque o valor de TOKEN abaixo por um valor secreto só seu - o
       mesmo valor tem que ser configurado em VisaoPlanilhas.psm1
       ($script:TokenWebAppInventario).
    4. Confirme que SPREADSHEET_ID abaixo bate com o ID da planilha do
       Visão (já preenchido com o mesmo ID usado em VisaoPlanilhas.psm1):
       1_2aZhFgplRqCdPVV_lq4XJT9wgqkfbZpEFZRu1Zu9_I
    5. Menu "Implantar" > "Nova implantação" > tipo "Aplicativo da web".
       - "Executar como": Eu (sua conta) - precisa ter permissão de
         EDIÇÃO na planilha, senão a gravação falha.
       - "Quem tem acesso": Qualquer pessoa.
    6. Na primeira implantação o Google vai pedir para autorizar o script
       a acessar suas planilhas - autorize (tela de "app não verificado"
       é normal, clique em Avançado > Acessar [nome do projeto]).
    7. Copie a URL do "Aplicativo da web" (termina em /exec) - é essa URL
       que vai em $script:UrlWebAppInventario (VisaoPlanilhas.psm1).
    8. Sempre que EDITAR este script depois, é preciso fazer uma NOVA
       implantação (ou "Gerenciar implantações" > editar > Nova versão) -
       só salvar o código não atualiza a URL /exec já publicada.
*/

var SPREADSHEET_ID = "1_2aZhFgplRqCdPVV_lq4XJT9wgqkfbZpEFZRu1Zu9_I";
var NOME_ABA = "INVENTARIO";
var TOKEN = "TROQUE_ESTE_VALOR_POR_UM_SEGREDO_SEU";
var CABECALHO = ["Zona", "Sede", "IP", "Hostname", "Tipo", "Modelo", "DetectadoPor", "Vnc", "Rc", "VersaoSis", "Instalador", "UltimaAtualizacao", "Tecnico"];

function doPost(e) {
  try {
    var params = JSON.parse(e.postData.contents);

    if (params.token !== TOKEN) {
      return responderJson({ ok: false, erro: "token invalido" });
    }
    if (!params.zona || !params.linhas || !params.linhas.length) {
      return responderJson({ ok: false, erro: "zona ou linhas ausente/vazia" });
    }

    var planilha = SpreadsheetApp.openById(SPREADSHEET_ID);
    var aba = planilha.getSheetByName(NOME_ABA);
    if (!aba) {
      aba = planilha.insertSheet(NOME_ABA);
      aba.appendRow(CABECALHO);
    }

    var agora = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd HH:mm:ss");
    var zonaPad = String(params.zona);
    var sede = params.sede || "";
    var tecnico = params.tecnico || "";

    // Le a aba inteira UMA vez e indexa por "Zona|IP" - evita procurar
    // linha por linha pra cada IP recebido (uma varredura manda ate 254
    // de uma vez).
    var dados = aba.getDataRange().getValues();
    var indice = {}; // "Zona|IP" -> numero da linha (1-based, ja contando o cabecalho)
    for (var i = 1; i < dados.length; i++) {
      var chave = String(dados[i][0]).trim() + "|" + String(dados[i][2]).trim();
      indice[chave] = i + 1;
    }

    var linhasNovas = [];
    var atualizacoes = 0;
    for (var j = 0; j < params.linhas.length; j++) {
      var l = params.linhas[j];
      if (!l.ip) continue;
      var chaveAtual = zonaPad + "|" + String(l.ip).trim();
      var linhaValores = [
        zonaPad, sede, l.ip, l.hostname || "", l.tipo || "", l.modelo || "",
        l.detectadoPor || "", l.vnc || "", l.rc || "", l.sis || "", l.instalador || "",
        agora, tecnico
      ];
      if (indice[chaveAtual]) {
        aba.getRange(indice[chaveAtual], 1, 1, CABECALHO.length).setValues([linhaValores]);
        atualizacoes++;
      } else {
        linhasNovas.push(linhaValores);
      }
    }
    if (linhasNovas.length) {
      aba.getRange(aba.getLastRow() + 1, 1, linhasNovas.length, CABECALHO.length).setValues(linhasNovas);
    }

    return responderJson({ ok: true, atualizadas: atualizacoes, novas: linhasNovas.length });
  } catch (err) {
    return responderJson({ ok: false, erro: String(err) });
  }
}

function doGet(e) {
  // So pra "clasp run"/teste manual conseguir ler de volta sem precisar
  // de um doPost - devolve as ultimas N linhas da aba (sem token, so
  // leitura; nao expoe nada que a propria planilha ja nao exponha pra
  // quem tem acesso a ela).
  var planilha = SpreadsheetApp.openById(SPREADSHEET_ID);
  var aba = planilha.getSheetByName(NOME_ABA);
  if (!aba) { return responderJson({ ok: true, linhas: [] }); }
  var dados = aba.getDataRange().getValues();
  var n = Math.min(5, dados.length - 1);
  var ultimas = n > 0 ? dados.slice(dados.length - n) : [];
  return responderJson({ ok: true, total: dados.length - 1, ultimas: ultimas });
}

function responderJson(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
