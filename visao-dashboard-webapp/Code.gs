/*
  Visao Web (Trilha B, Fase 2 - Passo 1: indicadores reais por campanha
  pro gestor, com menu de abas no estilo DICON Web + modulo de acesso).

  Implantado como Web App "Executar como: Usuário com acesso ao app da
  Web" + "Quem pode acessar: Qualquer pessoa em TRE-MA..." - mesmo
  padrão do DICON Web (restrição nativa de domínio do Apps Script, sem
  nenhum código de OAuth customizado). O CONTROLE DE ACESSO de verdade
  (quem pode abrir o app, e quem é admin) é feito por CIMA disso, via a
  aba ACESSO_WEB (ver verificarAcesso_) - ver comentario la.

  Le a MESMA planilha do Visao: "Zonas" (quais zonas existem/qual
  município cada uma pertence), "CAMPANHAS" (requisitos de versão por
  campanha), "INVENTARIO" (o que já foi escaneado, com versão de cada
  Sistema Eleitoral extra desde a Fase 1.5) e "ACESSO_WEB" (quem pode
  usar o Visão Web e com qual papel).

  Regra de "zona concluída" (decidida com o usuário, 2026-09-09):
  2 ou mais máquinas atendendo TODOS os requisitos da campanha
  selecionada = concluída (verde escuro). 1 máquina = verde claro.
  0 máquinas = vermelho (nunca escaneada OU escaneada sem nenhuma
  máquina pronta - as duas contam igual, por pedido do usuário).

  Abas (decididas com o usuário, 2026-09-09):
  - Painel: visao GERAL, nao depende de campanha (total de maquinas/
    zonas, por sistema com a versao mais nova, atividade recente) -
    aqui tambem vai entrar, numa fase bem mais pra frente, indicador de
    chamados do GLPI.
  - Campanhas: cards de todas as campanhas na 1a linha + um bloco
    destacado (com o seletor de campanha) reunindo Por Modelo/Zonas
    mais adiantadas/Zonas mais atrasadas + busca/filtro de maquinas
    (estilo aba "Vistorias" do DICON Web) logo abaixo, ja filtrada pela
    campanha escolhida no bloco.
  - Mapa: seletor de campanha proprio (local, nao mais global) + o
    mapa colorido.
  - Acesso: so visivel/editavel pra quem tem Papel=admin em ACESSO_WEB
    (estilo DICON Web - tabela de email/papel/ativo/observacao).

  "Por Rota"/"Por Técnico" ficaram de fora desta fatia por pedido
  explícito do usuário (2026-09-09) - implementação futura, quando a
  feature de Rotas/Roteiros sazonais existir e o Inventário passar a
  gravar nome do técnico (hoje só grava o usuário Windows local).
*/

// Ambiente (2026-09-09) - PRODUCAO. A copia de homologacao
// ("Visao - Dashboard - HOMOLOG", projeto Apps Script SEPARADO) e' o
// MESMO codigo com so 2 constantes trocadas (AMBIENTE e SPREADSHEET_ID)
// - mesmo espirito do DICON (achado inspecionando o codigo real dele:
// "um projeto por ambiente, sem tocar no resto do codigo"), so que sem
// Script Properties (tentativa de automatizar via "clasp run" ja
// falhou nesta maquina antes, ver memoria da sessao) - aqui a
// diferenca fica em 2 linhas bem marcadas, sincronizadas manualmente
// (mesmo arquivo, so essas 2 linhas mudam) toda vez que uma alteracao
// e' replicada pro projeto homolog.
var AMBIENTE = "homologacao"; // "producao" | "homologacao" - unica linha que muda entre os 2 projetos junto com SPREADSHEET_ID
var SPREADSHEET_ID = "1NVSQBPx8rtpPv1L9AP4o1a_11WlazjsoFF73tdcgq5M";
var MAPS_API_KEY = "AIzaSyAsN8Dma8pdBx9UPcS57JlC2Qgvuca0_wo";
var ABA_ACESSO = "ACESSO_WEB";
var EMAIL_ADMIN_BOOTSTRAP = "george.castro@tre-ma.jus.br";

// Favicon (2026-09-09) - achado inspecionando o projeto real do DICON
// Web (web/Console.js, funcao webConsolePagina): um <link rel="icon">
// dentro do proprio HTML NAO funciona pra Web App do Apps Script (o
// HTML fica preso no sandbox IFRAME que o Apps Script usa por baixo -
// quem controla o icone da aba do navegador e' o wrapper de FORA, que
// e' do Google). A API que funciona de verdade e' HtmlOutput.setFaviconUrl()
// - so aceita URL publica de verdade (nao data: URI) - por isso o
// icone fica hospedado no repositorio Visao-Web (GitHub, tornado
// publico especificamente pra isso, 2026-09-09).
var WEB_FAVICON_URL = "https://raw.githubusercontent.com/gamcastro/Visao-Web/main/assets/marca/icones/visao-192.png";

function obterColunasInventario_() {
  // Achado ao vivo (2026-09-09): NAO da pra montar isso como "var" no
  // nivel raiz do arquivo - o Apps Script executa o codigo de nivel
  // raiz de CADA arquivo .gs numa ordem que nao segue a ordem que a
  // gente criou os arquivos (aqui, alfabetica: "Code.gs" roda antes de
  // "VersaoCompare.gs"), entao SISTEMAS_ELEITORAIS_EXTRA (definido em
  // VersaoCompare.gs) ainda nao existiria no momento em que este
  // arquivo tentasse usa-lo no nivel raiz. Uma FUNCAO (chamada de
  // dentro de outra funcao, nunca no nivel raiz) so roda depois que
  // TODOS os arquivos ja carregaram, entao nao tem esse problema.
  return ["Zona", "Sede", "IP", "Hostname", "Tipo", "Modelo", "DetectadoPor", "Vnc", "Rc", "VersaoSis", "Instalador", "UltimaAtualizacao", "Tecnico"]
    .concat(SISTEMAS_ELEITORAIS_EXTRA.map(function (s) { return s.coluna; }));
}

// ============================================================
// Controle de acesso (aba ACESSO_WEB) - camada por CIMA da restricao
// nativa de dominio do Apps Script. O deploy deixa qualquer
// "@tre-ma.jus.br" ABRIR a URL; esta camada decide se essa pessoa
// especifica pode USAR o app (e com que papel).
// ============================================================
function obterOuCriarAbaAcesso_() {
  var planilha = SpreadsheetApp.openById(SPREADSHEET_ID);
  var aba = planilha.getSheetByName(ABA_ACESSO);
  if (!aba) {
    aba = planilha.insertSheet(ABA_ACESSO);
    aba.appendRow(["Email", "Papel", "Ativo", "Observacao"]);
    aba.appendRow([EMAIL_ADMIN_BOOTSTRAP, "admin", "TRUE", "bootstrap automatico"]);
    // Achado ao vivo (2026-09-09): sem isso, a PRIMEIRA leitura logo em
    // seguida (mesma execucao, "obterListaAcesso_" chamando
    // "getDataRange().getValues()" na sequencia) pode nao enxergar a
    // linha de bootstrap que acabou de ser gravada - o admin recem
    // criado via bootstrap ficava "sem acesso" na primeira abertura,
    // mesmo com a linha certa ja gravada na planilha (confirmado lendo
    // direto por fora, na hora, os dados ja estavam la). flush() forca
    // a gravacao a ficar visivel pra leitura antes de devolver a aba.
    SpreadsheetApp.flush();
  }
  return aba;
}

function obterListaAcesso_() {
  var aba = obterOuCriarAbaAcesso_();
  var dados = aba.getDataRange().getValues();
  var lista = [];
  for (var i = 1; i < dados.length; i++) {
    var email = String(dados[i][0]).trim();
    if (!email) continue;
    lista.push({
      email: email,
      papel: String(dados[i][1]).trim().toLowerCase(),
      ativo: String(dados[i][2]).trim().toUpperCase() === "TRUE",
      observacao: dados[i][3] || ""
    });
  }
  return lista;
}

function verificarAcesso_() {
  var emailAtual = Session.getActiveUser().getEmail();
  var registro = obterListaAcesso_().filter(function (r) { return r.email.toLowerCase() === emailAtual.toLowerCase(); })[0];
  if (!registro || !registro.ativo) { return { temAcesso: false, email: emailAtual, papel: null }; }
  return { temAcesso: true, email: emailAtual, papel: registro.papel };
}

function exigirAdmin_() {
  var acesso = verificarAcesso_();
  if (acesso.papel !== "admin") { throw new Error("Sem permissao - só administradores podem fazer isso."); }
  return acesso;
}

function obterListaAcessoParaCliente() {
  exigirAdmin_();
  return obterListaAcesso_();
}

function salvarAcesso(email, papel, observacao) {
  exigirAdmin_();
  email = String(email || "").trim();
  papel = String(papel || "leitura").trim().toLowerCase();
  if (!email) { throw new Error("Informe um e-mail."); }
  if (papel !== "admin" && papel !== "leitura") { papel = "leitura"; }
  var aba = obterOuCriarAbaAcesso_();
  var dados = aba.getDataRange().getValues();
  var achou = false;
  for (var i = 1; i < dados.length; i++) {
    if (String(dados[i][0]).trim().toLowerCase() === email.toLowerCase()) {
      aba.getRange(i + 1, 2, 1, 3).setValues([[papel, "TRUE", observacao || ""]]);
      achou = true;
      break;
    }
  }
  if (!achou) { aba.appendRow([email, papel, "TRUE", observacao || ""]); }
  SpreadsheetApp.flush(); // mesmo motivo do bootstrap - grava e le de volta na mesma execucao
  return obterListaAcesso_();
}

function desativarAcesso(email) {
  exigirAdmin_();
  var aba = obterOuCriarAbaAcesso_();
  var dados = aba.getDataRange().getValues();
  for (var i = 1; i < dados.length; i++) {
    if (String(dados[i][0]).trim().toLowerCase() === String(email || "").trim().toLowerCase()) {
      aba.getRange(i + 1, 3).setValue("FALSE");
      break;
    }
  }
  SpreadsheetApp.flush();
  return obterListaAcesso_();
}

function reativarAcesso(email) {
  exigirAdmin_();
  var aba = obterOuCriarAbaAcesso_();
  var dados = aba.getDataRange().getValues();
  for (var i = 1; i < dados.length; i++) {
    if (String(dados[i][0]).trim().toLowerCase() === String(email || "").trim().toLowerCase()) {
      aba.getRange(i + 1, 3).setValue("TRUE");
      break;
    }
  }
  SpreadsheetApp.flush();
  return obterListaAcesso_();
}

// ============================================================
// Ponto de entrada Web App.
// ============================================================
function doGet(e) {
  var acesso = verificarAcesso_();
  if (!acesso.temAcesso) {
    return HtmlService.createHtmlOutput(
      '<div style="font-family:Arial,Helvetica,sans-serif;padding:80px 20px;text-align:center;color:#334">' +
      '<h2>Sem acesso ao Visão Web</h2>' +
      '<p>A conta <b>' + acesso.email + '</b> ainda não está liberada.</p>' +
      '<p>Peça a um administrador do Visão Web pra te adicionar.</p>' +
      '</div>'
    ).setTitle('Visão Web - Sem acesso');
  }

  var campanhaPedida = e && e.parameter && e.parameter.campanha;
  var brutos = coletarDadosBrutos_();
  var dadosGeraisJson = JSON.stringify(montarDadosGerais_(brutos));
  var dadosCampanhasJson = JSON.stringify(montarDadosCampanhas_(brutos, campanhaPedida));

  // "?app=mobile" (2026-09-09) - espelho responsivo so-leitura, nos
  // moldes do DICON Mobile (mesmo Web App, view separada - decisao ja
  // registrada no plano desde o desenho original da Trilha B). Reusa OS
  // MESMOS dados/calculos de montarDadosGerais_/montarDadosCampanhas_ -
  // so muda o template HTML.
  var modo = (e && e.parameter && e.parameter.app) || 'web';
  var saida;
  if (modo === 'mobile') {
    var templateMobile = HtmlService.createTemplateFromFile('Mobile');
    templateMobile.ambiente = AMBIENTE;
    templateMobile.usuarioAtualJson = JSON.stringify(acesso);
    templateMobile.dadosGeraisJson = dadosGeraisJson;
    templateMobile.dadosCampanhasJson = dadosCampanhasJson;
    saida = templateMobile.evaluate()
      .setTitle('Visão Mobile')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1');
  } else if (modo === 'tv') {
    // Painel TV (2026-09-09, "segunda fase" do plano original) - nos
    // moldes do Painel TV do DICON, mas SEM o indicador "em campo
    // agora"/pontos pulsando no mapa: aquilo depende de presenca em
    // tempo real do tecnico (checkin), que o Visao Desktop nao publica
    // (so publica no FIM da varredura, nao no INICIO) - divida tecnica
    // ja registrada no plano.
    //
    // Campanha exibida: "&campanha=" na URL vence; sem isso, usa a
    // "PadraoTV" marcada no modulo "Gerenciar campanhas" (ver
    // coletarDadosBrutos_/definirCampanhaPadraoTv); sem nenhuma marcada,
    // cai no MESMO fallback de sempre (1a campanha da planilha) dentro
    // de montarDadosCampanhas_/montarDadosMapa_. Por isso o TV recalcula
    // dadosCampanhasJson por conta propria (nao reusa o de cima, que e'
    // pro Web/Mobile e nao conhece "PadraoTV").
    var campanhaTv = campanhaPedida || brutos.campanhaPadraoTv;
    var templateTv = HtmlService.createTemplateFromFile('Tv');
    templateTv.ambiente = AMBIENTE;
    templateTv.mapsApiKey = MAPS_API_KEY;
    templateTv.dadosGeraisJson = dadosGeraisJson;
    templateTv.dadosCampanhasJson = JSON.stringify(montarDadosCampanhas_(brutos, campanhaTv));
    templateTv.dadosMapaJson = JSON.stringify(montarDadosMapa_(brutos, campanhaTv));
    saida = templateTv.evaluate()
      .setTitle('Visão TV')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1');
  } else {
    var template = HtmlService.createTemplateFromFile('Index');
    template.ambiente = AMBIENTE;
    template.mapsApiKey = MAPS_API_KEY;
    template.usuarioAtualJson = JSON.stringify(acesso);
    template.dadosGeraisJson = dadosGeraisJson;
    template.dadosCampanhasJson = dadosCampanhasJson;
    saida = template.evaluate()
      .setTitle('Visão Web')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1');
  }
  try { saida.setFaviconUrl(WEB_FAVICON_URL); } catch (err) { /* favicon e' opcional, nao pode quebrar a pagina */ }
  return saida;
}

function incluirArquivo_(nome) {
  return HtmlService.createHtmlOutputFromFile(nome).getContent();
}

function obterGeojsonMunicipios() {
  // Chamado via google.script.run SO quando a aba Mapa e aberta pela
  // primeira vez - o GeoJSON tem ~1.9MB, nao faz sentido carregar isso
  // se o gestor nunca clicar em "Mapa".
  return incluirArquivo_('dados_municipios');
}

// ============================================================
// Coleta dos dados brutos da planilha - UMA leitura por aba, reusada
// por todos os calculos abaixo.
// ============================================================
function coletarDadosBrutos_() {
  var planilha = SpreadsheetApp.openById(SPREADSHEET_ID);

  var sedePorZona = {}; // TODAS as zonas cadastradas, escaneadas ou nao
  var abaZonas = planilha.getSheetByName('Zonas');
  if (abaZonas) {
    var dadosZonas = abaZonas.getDataRange().getValues();
    for (var i = 1; i < dadosZonas.length; i++) {
      var zona = String(dadosZonas[i][0]).trim();
      var sede = String(dadosZonas[i][1]).trim();
      if (zona) { sedePorZona[zona] = sede; }
    }
  }

  var campanhas = {}; // nome -> [{sistema, versaoMinima}]
  var abaCampanhas = planilha.getSheetByName('CAMPANHAS');
  if (abaCampanhas) {
    var dadosCampanhas = abaCampanhas.getDataRange().getValues();
    var cabecalhoCampanhas = dadosCampanhas[0].map(function (c) { return String(c).trim(); });
    var idxCampanha = cabecalhoCampanhas.indexOf('Campanha');
    var idxSistema = cabecalhoCampanhas.indexOf('Sistema');
    var idxVersaoMinima = cabecalhoCampanhas.indexOf('VersaoMinima');
    // "Ativo" (modulo de administracao de campanhas, 2026-09-09) - coluna
    // nova, pode nao existir ainda em planilhas antigas (indexOf -1).
    // Sem a coluna, ou com ela em branco, trata como ATIVA (compat com
    // as campanhas que ja existiam antes desta feature). So "FALSE"
    // literal desativa - e o que faz o card sumir da pagina principal
    // (ver definirAtivoCampanha_, CampanhasAdmin.gs).
    var idxAtivo = cabecalhoCampanhas.indexOf('Ativo');
    // "PadraoTV" (2026-09-09) - qual campanha abre sozinha no Painel TV
    // quando a URL nao tem "&campanha=" explicito (ver doGet, modo
    // 'tv') - definida pelo admin no modulo "Gerenciar campanhas"
    // (definirCampanhaPadraoTv, CampanhasAdmin.gs). So' uma campanha
    // deve estar marcada por vez; se nenhuma estiver (planilhas
    // antigas, coluna nem existe ainda), campanhaPadraoTv fica null e
    // quem decide o fallback e' o doGet (primeira campanha encontrada).
    var idxPadraoTv = cabecalhoCampanhas.indexOf('PadraoTV');
    var campanhaPadraoTv = null;
    for (var k = 1; k < dadosCampanhas.length; k++) {
      var nomeCampanha = String(dadosCampanhas[k][idxCampanha]).trim();
      var sistemaReq = String(dadosCampanhas[k][idxSistema]).trim();
      var versaoMinReq = String(dadosCampanhas[k][idxVersaoMinima]).trim();
      if (!nomeCampanha || !sistemaReq || !versaoMinReq) continue;
      if (idxAtivo !== -1 && String(dadosCampanhas[k][idxAtivo]).trim().toUpperCase() === 'FALSE') continue;
      if (!campanhas[nomeCampanha]) { campanhas[nomeCampanha] = []; }
      campanhas[nomeCampanha].push({ sistema: sistemaReq, versaoMinima: versaoMinReq });
      if (!campanhaPadraoTv && idxPadraoTv !== -1 && String(dadosCampanhas[k][idxPadraoTv]).trim().toUpperCase() === 'TRUE') {
        campanhaPadraoTv = nomeCampanha;
      }
    }
  }

  var linhasInventario = [];
  var abaInv = planilha.getSheetByName('INVENTARIO');
  if (abaInv) {
    var colunasInventario = obterColunasInventario_();
    var dadosInv = abaInv.getDataRange().getValues();
    for (var j = 1; j < dadosInv.length; j++) {
      var linha = dadosInv[j];
      var zonaInv = String(linha[0]).trim();
      if (!zonaInv) continue;
      var linhaObj = {};
      for (var c = 0; c < colunasInventario.length; c++) { linhaObj[colunasInventario[c]] = linha[c]; }
      linhasInventario.push(linhaObj);
    }
  }

  return { sedePorZona: sedePorZona, campanhas: campanhas, linhasInventario: linhasInventario, campanhaPadraoTv: campanhaPadraoTv || null };
}

// ============================================================
// Resumo (indicadores + tier por zona/municipio) de UMA campanha.
// ============================================================
function calcularResumoCampanha_(nomeCampanha, requisitos, sedePorZona, linhasInventario) {
  var prontasPorZona = {};
  linhasInventario.forEach(function (l) {
    var zonaInv = String(l.Zona).trim();
    if (!(zonaInv in prontasPorZona)) prontasPorZona[zonaInv] = 0;
    if (maquinaAtendeCampanha_(l, requisitos)) prontasPorZona[zonaInv]++;
  });

  var tierPorMunicipio = {};
  var zonasPorMunicipio = {};
  var zonasComTier = []; // flat - pra ranking POR ZONA (nao so por municipio)
  var totalZonas = 0;
  var zonasConcluidas = 0;
  for (var zonaChave in sedePorZona) {
    var sedeNome = sedePorZona[zonaChave];
    if (!sedeNome) continue;
    totalZonas++;

    var prontas = prontasPorZona[zonaChave] || 0;
    var tier = prontas >= 2 ? 2 : (prontas === 1 ? 1 : 0);
    if (tier === 2) zonasConcluidas++;

    zonasComTier.push({ zona: zonaChave, sede: sedeNome, tier: tier, prontas: prontas });

    var chaveMunicipio = sedeNome.toUpperCase();
    if (!(chaveMunicipio in tierPorMunicipio) || tier < tierPorMunicipio[chaveMunicipio]) {
      tierPorMunicipio[chaveMunicipio] = tier;
    }
    if (!zonasPorMunicipio[chaveMunicipio]) { zonasPorMunicipio[chaveMunicipio] = { nome: sedeNome, zonas: [] }; }
    zonasPorMunicipio[chaveMunicipio].zonas.push({ zona: zonaChave, tier: tier, prontas: prontas });
  }

  var pendentes = totalZonas - zonasConcluidas;
  var percentualCobertura = totalZonas > 0 ? Math.round((zonasConcluidas / totalZonas) * 100) : 0;

  return {
    nome: nomeCampanha,
    percentualCobertura: percentualCobertura,
    zonasConcluidas: zonasConcluidas,
    totalZonas: totalZonas,
    pendentes: pendentes,
    tierPorMunicipio: tierPorMunicipio,
    zonasPorMunicipio: zonasPorMunicipio,
    zonasComTier: zonasComTier
  };
}

function calcularRankingZonas_(zonasComTier) {
  var melhores = zonasComTier.slice().sort(function (a, b) { return b.tier - a.tier || a.zona - b.zona; }).slice(0, 5);
  var piores = zonasComTier.slice().sort(function (a, b) { return a.tier - b.tier || a.zona - b.zona; }).slice(0, 5);
  return { melhores: melhores, piores: piores };
}

function calcularPorModelo_(requisitos, linhasInventario) {
  var porModelo = {};
  linhasInventario.forEach(function (l) {
    var modelo = (l.Modelo && l.Modelo !== '-') ? l.Modelo : '(sem modelo)';
    if (!porModelo[modelo]) porModelo[modelo] = { total: 0, prontas: 0 };
    porModelo[modelo].total++;
    if (maquinaAtendeCampanha_(l, requisitos)) porModelo[modelo].prontas++;
  });
  return Object.keys(porModelo)
    .map(function (modelo) { return { modelo: modelo, total: porModelo[modelo].total, prontas: porModelo[modelo].prontas }; })
    .sort(function (a, b) { return b.prontas - a.prontas; });
}

function calcularPorSistemaExigido_(requisitos, sedePorZona, linhasInventario) {
  // Card "Por Sistema exigido" do Painel TV (2026-09-09) - substitui o
  // antigo card "Por Campanha" (o usuario achou sem sentido misturar
  // TODAS as campanhas num painel que ja foca numa so'). Pra CADA
  // requisito da campanha escolhida, conta em quantas Zonas Eleitorais
  // ja tem PELO MENOS 1 maquina atendendo aquele sistema especifico
  // (instalado + versao >= minima) - mostra qual sistema especifico
  // esta' travando mais zonas, informacao que nem o mapa nem o card de
  // "por modelo" mostram.
  var totalZonas = Object.keys(sedePorZona).length;
  return requisitos.map(function (req) {
    var coluna = resolverColunaPorNomeSistema_(req.sistema);
    var zonasAtendem = {};
    linhasInventario.forEach(function (l) {
      var instalado = coluna ? l[coluna] : null;
      if (!instalado || instalado === '-') return;
      var cmp = compararVersaoSistema(instalado, req.versaoMinima);
      if (cmp !== null && cmp >= 0) { zonasAtendem[String(l.Zona).trim()] = true; }
    });
    return { sistema: req.sistema, versaoMinima: req.versaoMinima, zonasProntas: Object.keys(zonasAtendem).length, totalZonas: totalZonas };
  });
}

function calcularZonasConcluidasRecentes_(requisitos, sedePorZona, linhasInventario, limite) {
  // Scroller do rodape do Painel TV (2026-09-09) - antes mostrava
  // QUALQUER atividade recente (mesmo criterio do card "Atividade
  // recente"); o usuario pediu especificamente as ultimas zonas que
  // viraram CONCLUIDA (2+ maquinas prontas) pra campanha escolhida.
  // Achado/aproximacao documentada: o Visao nao guarda "o momento exato
  // em que a zona cruzou pra concluida" - usa como proxy a hora da
  // ULTIMA varredura registrada naquela zona (na pratica e' quase
  // sempre a mesma hora em que ela passa a status concluido).
  limite = limite || 15;
  var prontasPorZona = {};
  var ultimaPorZona = {};
  linhasInventario.forEach(function (l) {
    var zonaInv = String(l.Zona).trim();
    if (!(zonaInv in prontasPorZona)) prontasPorZona[zonaInv] = 0;
    if (maquinaAtendeCampanha_(l, requisitos)) prontasPorZona[zonaInv]++;
    if (!ultimaPorZona[zonaInv] || new Date(l.UltimaAtualizacao) > new Date(ultimaPorZona[zonaInv].quando)) {
      ultimaPorZona[zonaInv] = { zona: l.Zona, sede: l.Sede, quando: l.UltimaAtualizacao };
    }
  });
  var concluidas = [];
  for (var zona in sedePorZona) {
    if ((prontasPorZona[zona] || 0) >= 2 && ultimaPorZona[zona]) { concluidas.push(ultimaPorZona[zona]); }
  }
  return concluidas.sort(function (a, b) { return new Date(b.quando) - new Date(a.quando); }).slice(0, limite);
}

function calcularListaBusca_(requisitos, linhasInventario) {
  // Uma linha por maquina, com o status pra campanha escolhida - base
  // da busca/filtro da aba Campanhas (estilo "Vistorias" do DICON).
  return linhasInventario.map(function (l) {
    return {
      ip: l.IP, hostname: l.Hostname, zona: l.Zona, sede: l.Sede, modelo: l.Modelo,
      pronta: maquinaAtendeCampanha_(l, requisitos), quando: l.UltimaAtualizacao
    };
  });
}

function calcularPorSistema_(linhasInventario) {
  // "Versao mais nova" aqui e a MAIOR versao OBSERVADA nos dados atuais
  // do Inventario - o Apps Script nao tem acesso a uma "versao oficial
  // de referencia" (isso so existe do lado do servidor PowerShell,
  // Import-TabelaVersoes/Get-VersoesRemoto, nao publicado na planilha
  // compartilhada ainda) - documentado como simplificacao conhecida.
  var colunas = ['VersaoSis'].concat(SISTEMAS_ELEITORAIS_EXTRA.map(function (s) { return s.coluna; }));
  var titulos = { VersaoSis: 'SIS' };
  SISTEMAS_ELEITORAIS_EXTRA.forEach(function (s) { titulos[s.coluna] = s.titulo; });

  return colunas.map(function (c) {
    var versoesInstaladas = linhasInventario.map(function (l) { return l[c]; }).filter(function (v) { return v && v !== '-'; });
    var versaoMaisNova = null;
    versoesInstaladas.forEach(function (v) {
      if (versaoMaisNova === null) { versaoMaisNova = v; return; }
      var cmp = compararVersaoSistema(v, versaoMaisNova);
      if (cmp !== null && cmp > 0) { versaoMaisNova = v; }
    });
    var naVersaoMaisNova = versaoMaisNova ? versoesInstaladas.filter(function (v) { return v === versaoMaisNova; }).length : 0;
    return { sistema: titulos[c], totalInstaladas: versoesInstaladas.length, versaoMaisNova: versaoMaisNova, naVersaoMaisNova: naVersaoMaisNova };
  }).sort(function (a, b) { return b.totalInstaladas - a.totalInstaladas; });
}

function calcularUltimaAtividadePorZona_(linhasInventario) {
  // Opcao A (decidida com o usuario, 2026-09-09): UMA linha por zona -
  // so a atividade MAIS RECENTE dela, nao um evento por varredura (a
  // versao anterior repetia a mesma zona varias vezes e confundia).
  var porZona = {};
  linhasInventario.forEach(function (l) {
    var chave = l.Zona;
    if (!porZona[chave] || new Date(l.UltimaAtualizacao) > new Date(porZona[chave].quando)) {
      porZona[chave] = { zona: l.Zona, sede: l.Sede, quando: l.UltimaAtualizacao };
    }
  });
  return Object.keys(porZona).map(function (k) { return porZona[k]; })
    .sort(function (a, b) { return new Date(b.quando) - new Date(a.quando); })
    .slice(0, 10);
}

function calcularResumoHoje_(linhasInventario) {
  // Opcao B (decidida com o usuario, 2026-09-09): resumo do dia
  // calendario (fuso do proprio script, mesmo usado pra gravar
  // UltimaAtualizacao) - "Host/PC identificados" conta SO Tipo="Host /
  // PC" (exclui impressora/gateway/nobreak/telefone VOIP/maquina
  // possivelmente desligada - nao sao "Host/PC" de verdade).
  //
  // Achado ao vivo (2026-09-09): "UltimaAtualizacao" e gravado como
  // texto ("yyyy-MM-dd HH:mm:ss") mas o Google Sheets converte SOZINHO
  // pra um valor de data/hora de verdade (mesmo comportamento ja visto
  // com "2.1" virando data - aqui e ate esperado, ja que o conteudo E
  // uma data) - "getValues()" devolve um objeto Date, nao mais a
  // string original. Comparacao por PREFIXO DE TEXTO ("2026-09-09...")
  // quebraria silenciosamente (Date vira "Wed Sep 09 2026..." quando
  // vira string). Reformata pelo mesmo fuso antes de comparar, pra
  // funcionar tanto com Date quanto com string.
  var hoje = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd");
  var zonasHoje = {};
  var hostPcHoje = 0;
  linhasInventario.forEach(function (l) {
    if (!l.UltimaAtualizacao) return;
    var dataLinha = Utilities.formatDate(new Date(l.UltimaAtualizacao), Session.getScriptTimeZone(), "yyyy-MM-dd");
    if (dataLinha !== hoje) return;
    zonasHoje[l.Zona] = true;
    if (l.Tipo === "Host / PC") { hostPcHoje++; }
  });
  return { zonasHoje: Object.keys(zonasHoje).length, hostPcHoje: hostPcHoje };
}

function calcularAtividadeUltimosDias_(linhasInventario, dias) {
  // Grafico "Atividade dos ultimos 7 dias" (Painel, 2026-09-09) - mesma
  // logica de fuso ja usada em calcularResumoHoje_ (UltimaAtualizacao
  // pode vir como Date OU string dependendo de como o Sheets guardou,
  // reformata pelo fuso do script antes de comparar). Devolve um item
  // por dia, do mais antigo pro mais recente (hoje por ultimo), mesmo
  // pra dias sem nenhuma varredura (zeros - o grafico de barras precisa
  // dos 7 pontos pra manter a escala de tempo legivel).
  dias = dias || 7;
  var tz = Session.getScriptTimeZone();
  var porDia = {};
  var ordemDias = [];
  for (var d = dias - 1; d >= 0; d--) {
    var dataRef = new Date();
    dataRef.setDate(dataRef.getDate() - d);
    var chave = Utilities.formatDate(dataRef, tz, "yyyy-MM-dd");
    porDia[chave] = { zonas: {}, hostPc: 0 };
    ordemDias.push(chave);
  }
  linhasInventario.forEach(function (l) {
    if (!l.UltimaAtualizacao) return;
    var chave = Utilities.formatDate(new Date(l.UltimaAtualizacao), tz, "yyyy-MM-dd");
    if (!porDia[chave]) return; // fora da janela dos ultimos N dias
    porDia[chave].zonas[l.Zona] = true;
    if (l.Tipo === "Host / PC") { porDia[chave].hostPc++; }
  });
  return ordemDias.map(function (chave) {
    var partes = chave.split("-");
    return { data: chave, rotulo: partes[2] + "/" + partes[1], zonas: Object.keys(porDia[chave].zonas).length, hostPc: porDia[chave].hostPc };
  });
}

function calcularVisaoGeralCrossCampanha_(campanhas, sedePorZona, linhasInventario) {
  var zonasComAlgumaCampanha = {};
  Object.keys(campanhas).forEach(function (nomeCampanha) {
    var requisitos = campanhas[nomeCampanha];
    var prontasPorZona = {};
    linhasInventario.forEach(function (l) {
      var zonaInv = String(l.Zona).trim();
      if (!(zonaInv in prontasPorZona)) prontasPorZona[zonaInv] = 0;
      if (maquinaAtendeCampanha_(l, requisitos)) prontasPorZona[zonaInv]++;
    });
    for (var zona in prontasPorZona) {
      if (prontasPorZona[zona] >= 2) zonasComAlgumaCampanha[zona] = true;
    }
  });
  var totalZonas = Object.keys(sedePorZona).length;
  var comAlgumaCampanha = Object.keys(zonasComAlgumaCampanha).length;
  return { totalZonas: totalZonas, comAlgumaCampanha: comAlgumaCampanha, semNenhuma: totalZonas - comAlgumaCampanha };
}

// ============================================================
// Painel (visao geral, NAO depende de campanha).
// ============================================================
function montarDadosGerais_(brutos) {
  return {
    ok: true,
    totalMaquinas: brutos.linhasInventario.length,
    totalZonas: Object.keys(brutos.sedePorZona).length,
    visaoGeral: calcularVisaoGeralCrossCampanha_(brutos.campanhas, brutos.sedePorZona, brutos.linhasInventario),
    porSistema: calcularPorSistema_(brutos.linhasInventario),
    ultimaAtividadePorZona: calcularUltimaAtividadePorZona_(brutos.linhasInventario),
    resumoHoje: calcularResumoHoje_(brutos.linhasInventario),
    atividade7Dias: calcularAtividadeUltimosDias_(brutos.linhasInventario, 7),
    atualizadoEm: new Date().toISOString()
  };
}
function obterDadosGerais() {
  return montarDadosGerais_(coletarDadosBrutos_());
}

// ============================================================
// Campanhas (cards de todas + detalhe da campanha escolhida: por
// modelo, ranking de ZONAS, lista pra busca/filtro).
// ============================================================
function montarDadosCampanhas_(brutos, campanhaPedida) {
  var nomesCampanhas = Object.keys(brutos.campanhas);
  var campanhaEscolhida = (campanhaPedida && brutos.campanhas[campanhaPedida]) ? campanhaPedida : nomesCampanhas[0];

  var resumoPorCampanha = nomesCampanhas.map(function (nome) {
    var r = calcularResumoCampanha_(nome, brutos.campanhas[nome], brutos.sedePorZona, brutos.linhasInventario);
    return { nome: r.nome, percentualCobertura: r.percentualCobertura, zonasConcluidas: r.zonasConcluidas, totalZonas: r.totalZonas, pendentes: r.pendentes };
  });

  var resumoSelecionado = campanhaEscolhida
    ? calcularResumoCampanha_(campanhaEscolhida, brutos.campanhas[campanhaEscolhida], brutos.sedePorZona, brutos.linhasInventario)
    : null;
  var requisitosSelecionados = campanhaEscolhida ? brutos.campanhas[campanhaEscolhida] : [];

  return {
    ok: true,
    campanhas: nomesCampanhas,
    campanhaEscolhida: campanhaEscolhida || null,
    resumoPorCampanha: resumoPorCampanha,
    ranking: resumoSelecionado ? calcularRankingZonas_(resumoSelecionado.zonasComTier) : { melhores: [], piores: [] },
    porModelo: calcularPorModelo_(requisitosSelecionados, brutos.linhasInventario),
    listaBusca: calcularListaBusca_(requisitosSelecionados, brutos.linhasInventario),
    porSistemaExigido: calcularPorSistemaExigido_(requisitosSelecionados, brutos.sedePorZona, brutos.linhasInventario),
    zonasConcluidasRecentes: calcularZonasConcluidasRecentes_(requisitosSelecionados, brutos.sedePorZona, brutos.linhasInventario, 15),
    atualizadoEm: new Date().toISOString()
  };
}
function obterDadosCampanhas(campanhaEscolhida) {
  return montarDadosCampanhas_(coletarDadosBrutos_(), campanhaEscolhida);
}

// ============================================================
// Mapa (seletor de campanha proprio, tier por municipio/zona).
// ============================================================
function montarDadosMapa_(brutos, campanhaPedida) {
  var nomesCampanhas = Object.keys(brutos.campanhas);
  var campanhaEscolhida = (campanhaPedida && brutos.campanhas[campanhaPedida]) ? campanhaPedida : nomesCampanhas[0];
  var resumo = campanhaEscolhida
    ? calcularResumoCampanha_(campanhaEscolhida, brutos.campanhas[campanhaEscolhida], brutos.sedePorZona, brutos.linhasInventario)
    : null;
  return {
    ok: true,
    campanhas: nomesCampanhas,
    campanhaEscolhida: campanhaEscolhida || null,
    tierPorMunicipio: resumo ? resumo.tierPorMunicipio : {},
    zonasPorMunicipio: resumo ? Object.keys(resumo.zonasPorMunicipio).reduce(function (acc, k) { acc[k] = resumo.zonasPorMunicipio[k].zonas; return acc; }, {}) : {}
  };
}
function obterDadosMapa(campanhaPedida) {
  return montarDadosMapa_(coletarDadosBrutos_(), campanhaPedida);
}
