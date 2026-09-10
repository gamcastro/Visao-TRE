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
    N..V = uma coluna por Sistema Eleitoral extra (Fase 1.5 - ver
    COLUNAS_SISTEMAS_EXTRA abaixo), acrescentadas ao FINAL de propósito
    pra nunca deslocar A-M (linhas antigas continuam válidas).

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
       - "Quem tem acesso": Qualquer pessoa - ATENÇÃO: o valor
         equivalente no manifest (appsscript.json) é "ANYONE_ANONYMOUS",
         NÃO "ANYONE" (esse último ainda exige login Google - achado ao
         vivo, 2026-09-09). Implantando pela UI (como aqui) o rótulo
         certo já aparece direto como "Qualquer pessoa".
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
var CABECALHO_BASE = ["Zona", "Sede", "IP", "Hostname", "Tipo", "Modelo", "DetectadoPor", "Vnc", "Rc", "VersaoSis", "Instalador", "UltimaAtualizacao", "Tecnico"];
// Fase 1.5 - mesmos nomes de "Coluna" de $script:SistemasEleitoraisExtra
// (VisaoServidor.ps1) - se um sistema novo for adicionado lá, precisa
// lembrar de espelhar aqui também (dívida técnica já documentada no
// plano - Apps Script não acessa o servidor PowerShell pra ler isso
// dinamicamente).
var COLUNAS_SISTEMAS_EXTRA = ["Bitlocker", "Gedai", "Holocron", "PadaUe", "Fbr", "TransportadorTdtot", "ExecJava", "TransportadorHmg", "CertificadoP12"];
var CABECALHO = CABECALHO_BASE.concat(COLUNAS_SISTEMAS_EXTRA);

function doPost(e) {
  try {
    var params = JSON.parse(e.postData.contents);

    if (params.token !== TOKEN) {
      return responderJson({ ok: false, erro: "token invalido" });
    }
    if (!params.zona || !params.linhas) {
      return responderJson({ ok: false, erro: "zona ou linhas ausente" });
    }
    // "linhas" vazio e um resultado LEGITIMO (zona escaneada, zero
    // maquinas online agora) - so zona/linhas ausentes de verdade sao
    // erro. Como "substitui a zona inteira" (ver abaixo), isso tambem
    // serve pra zerar de proposito uma zona (ex: limpeza de teste) sem
    // precisar de uma acao separada de "limpar".

    var planilha = SpreadsheetApp.openById(SPREADSHEET_ID);
    var aba = planilha.getSheetByName(NOME_ABA);
    if (!aba) {
      aba = planilha.insertSheet(NOME_ABA);
      aba.appendRow(CABECALHO);
    } else if (aba.getLastColumn() < CABECALHO.length) {
      // Fase 1.5 - migracao de header sem quebrar linhas antigas: se a
      // aba ja existe mas foi criada ANTES das colunas N-V existirem,
      // so reescreve a linha 1 (cabecalho) - linhas de dados antigas
      // (2+) ficam com as colunas novas em branco ate serem
      // re-upsertadas na proxima varredura daquela Zona+IP.
      aba.getRange(1, 1, 1, CABECALHO.length).setValues([CABECALHO]);
    }
    // Chamado SEMPRE (nao so na criacao/migracao) - de proposito,
    // auto-corretivo: a primeira versao desta Fase 1.5 so formatava no
    // momento da migracao, e como a migracao ja tinha rodado antes
    // desta linha existir, o sintoma (valor tipo "2.1" virando data
    // sozinho) continuaria pra sempre sem essa chamada incondicional.
    formatarColunasSistemasComoTexto_(aba);

    var agora = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd HH:mm:ss");
    // Comparado sempre como NUMERO dos dois lados (achado ao vivo,
    // 2026-09-10 - ver correcao no ambiente de homologacao primeiro):
    // "022" (zero a esquerda) escrito numa celula do Sheets e
    // auto-convertido pra NUMERO puro (22) pelo proprio Google Sheets -
    // comparar como texto ("022" !== "22") nunca batia, entao o upsert
    // por chave abaixo NUNCA encontrava a linha existente e duplicava a
    // zona inteira a cada nova varredura (confirmado: uma zona rescaneada
    // 2x virou 508 linhas em vez de 254). Troca de estrategia: em vez de
    // upsert por IP (fragil), substitui a ZONA INTEIRA a cada publicacao
    // - cada varredura ja manda o resultado completo da zona mesmo, e
    // isso tem o efeito colateral bom de maquina desligada/baixada sumir
    // sozinha do Inventario no proximo re-scan, em vez de ficar presa.
    var zonaNum = Number(params.zona);
    var zonaTexto = String(params.zona);
    var sede = params.sede || "";
    var tecnico = params.tecnico || "";

    // Mantem so as linhas de OUTRAS zonas e reescreve tudo de uma vez (1
    // setValues) em vez de apagar linha por linha (deleteRow() num loop
    // e O(n^2) - cada chamada desloca fisicamente as linhas abaixo -
    // deu timeout no cliente com uma zona de 254 linhas, ver correcao
    // feita primeiro no ambiente de homologacao).
    var dados = aba.getDataRange().getValues();
    var linhasMantidas = [];
    for (var i = 1; i < dados.length; i++) {
      if (Number(dados[i][0]) !== zonaNum) {
        linhasMantidas.push(dados[i]);
      }
    }

    var linhasNovas = [];
    for (var j = 0; j < params.linhas.length; j++) {
      var l = params.linhas[j];
      if (!l.ip) continue;
      var valoresSistemas = COLUNAS_SISTEMAS_EXTRA.map(function (coluna) {
        return (l.sistemas && l.sistemas[coluna]) || "";
      });
      var linhaValores = [
        zonaTexto, sede, l.ip, l.hostname || "", l.tipo || "", l.modelo || "",
        l.detectadoPor || "", l.vnc || "", l.rc || "", l.sis || "", l.instalador || "",
        agora, tecnico
      ].concat(valoresSistemas);
      linhasNovas.push(linhaValores);
    }

    var linhasFinais = linhasMantidas.concat(linhasNovas);
    if (dados.length > 1) {
      aba.getRange(2, 1, dados.length - 1, CABECALHO.length).clearContent();
    }
    if (linhasFinais.length) {
      aba.getRange(2, 1, linhasFinais.length, CABECALHO.length).setValues(linhasFinais);
    }

    return responderJson({ ok: true, atualizadas: 0, novas: linhasNovas.length });
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

function formatarColunasSistemasComoTexto_(aba) {
  // Achado ao vivo (2026-09-09): o Google Sheets "adivinha" o tipo do
  // valor gravado via setValues() mesmo sendo uma string JS pura - um
  // valor tipo "2.1" pode virar DATA sozinho (ex: virou
  // "02/01/2026"), corrompendo a versao gravada. Forcar as colunas de
  // Sistemas Eleitorais extra (N em diante) como texto puro ("@")
  // resolve na origem - sem isso, qualquer versao no formato N.N pode
  // ser mal-interpretada dependendo do locale da planilha.
  var primeiraColunaSistemas = CABECALHO_BASE.length + 1;
  aba.getRange(1, primeiraColunaSistemas, aba.getMaxRows(), COLUNAS_SISTEMAS_EXTRA.length).setNumberFormat("@");
}

function responderJson(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
