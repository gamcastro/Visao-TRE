/*
  Modulo de administracao de campanhas (2026-09-09) - so admin (ver
  exigirAdmin_ em Code.gs). Cobre os 3 itens pedidos pelo usuario:
    1 - Criar campanhas (criarCampanha)
    2 - Desabilitar/reabilitar campanhas sem apagar (definirAtivoCampanha)
        - some do card da pagina principal (filtro em
        coletarDadosBrutos_, Code.gs), mas os dados continuam na aba.
    3 - Alterar campanha: editar versao de um requisito existente
        (salvarRequisito), acrescentar um sistema novo a uma campanha
        ja existente (adicionarRequisitoACampanha) ou remover um
        requisito (removerRequisito).

  Decisao confirmada com o usuario (2026-09-09): o campo "Sistema" usa
  LISTA FIXA (obterListaSistemasDisponiveis), nao texto livre - evita
  erro de digitacao que tornaria um requisito permanentemente
  impossivel de atender (resolverColunaPorNomeSistema_, VersaoCompare.gs,
  so casa por nome EXATO). Confirmado que isso nao quebra o Visao
  Desktop: o Desktop so faz comparacao de string na leitura da aba
  CAMPANHAS, sem validar schema - o dropdown so restringe o que ESTE
  formulario grava, usando os mesmos nomes canonicos (titulo dos 9
  Sistemas Eleitorais extra + "SIS") que o Desktop ja reconhece. A
  partir de agora o gerenciamento de campanhas e 100% por aqui -
  ninguem mais edita a aba CAMPANHAS na mao.

  Schema da aba "CAMPANHAS": uma linha por requisito (Campanha, Sistema,
  VersaoMinima - ja existiam) + "Ativo" (coluna nova, migrada sozinha no
  FINAL na primeira escrita por este modulo - ver obterCabecalhoCampanhas_).
  Todas as linhas de uma mesma campanha compartilham o mesmo Ativo -
  definirAtivoCampanha atualiza todas de uma vez.
*/

function obterListaSistemasDisponiveis() {
  // Dado de referencia (lista fixa pro dropdown) - leitura simples, nao
  // precisa ser admin pra buscar isso (so grava exige exigirAdmin_).
  return ["SIS"].concat(SISTEMAS_ELEITORAIS_EXTRA.map(function (s) { return s.titulo; }));
}

function obterAbaCampanhas_() {
  var planilha = SpreadsheetApp.openById(SPREADSHEET_ID);
  var aba = planilha.getSheetByName('CAMPANHAS');
  if (!aba) { throw new Error('Aba CAMPANHAS nao encontrada na planilha.'); }
  return aba;
}

function obterCabecalhoCampanhas_(aba) {
  var ultimaColuna = aba.getLastColumn();
  var header = aba.getRange(1, 1, 1, ultimaColuna).getValues()[0].map(function (c) { return String(c).trim(); });
  var idx = {
    campanha: header.indexOf('Campanha'),
    sistema: header.indexOf('Sistema'),
    versaoMinima: header.indexOf('VersaoMinima'),
    ativo: header.indexOf('Ativo'),
    padraoTv: header.indexOf('PadraoTV')
  };
  // Migracao automatica (mesmo padrao ja usado no Inventario, Fase 1.5)
  // - acrescenta a(s) coluna(s) que faltarem no FINAL, numa unica
  // reescrita de cabecalho; linhas antigas ficam em branco nelas
  // (tratado como "ativa"/"nao e' a padrao do TV" - ver
  // coletarDadosBrutos_).
  var faltando = [];
  if (idx.ativo === -1) { idx.ativo = header.length + faltando.length; faltando.push('Ativo'); }
  if (idx.padraoTv === -1) { idx.padraoTv = header.length + faltando.length; faltando.push('PadraoTV'); }
  if (faltando.length) {
    aba.getRange(1, header.length + 1, 1, faltando.length).setValues([faltando]);
    SpreadsheetApp.flush();
  }
  return idx;
}

function validarSistemaPermitido_(sistema) {
  var permitidos = obterListaSistemasDisponiveis();
  var achou = permitidos.some(function (s) { return s.toLowerCase() === String(sistema || '').trim().toLowerCase(); });
  if (!achou) { throw new Error('Sistema "' + sistema + '" nao esta na lista permitida.'); }
  return String(sistema).trim();
}

function validarVersaoMinima_(versao) {
  versao = String(versao || '').trim();
  if (!versao || !/^\d+(\.\d+)*$/.test(versao)) { throw new Error('Versao minima invalida: "' + versao + '" (use so numeros e pontos, ex: 3.47).'); }
  return versao;
}

function obterCampanhasAdmin() {
  exigirAdmin_();
  var aba = obterAbaCampanhas_();
  var idx = obterCabecalhoCampanhas_(aba);
  var dados = aba.getDataRange().getValues();
  var porNome = {};
  var ordem = [];
  for (var i = 1; i < dados.length; i++) {
    var nome = String(dados[i][idx.campanha]).trim();
    var sistema = String(dados[i][idx.sistema]).trim();
    if (!nome || !sistema) continue;
    var versaoMinima = String(dados[i][idx.versaoMinima]).trim();
    var ativoTexto = String(dados[i][idx.ativo]).trim().toUpperCase();
    var ativo = ativoTexto !== 'FALSE'; // branco ou TRUE = ativo (compat)
    var padraoTv = String(dados[i][idx.padraoTv]).trim().toUpperCase() === 'TRUE';
    if (!porNome[nome]) { porNome[nome] = { nome: nome, ativo: ativo, padraoTv: padraoTv, requisitos: [] }; ordem.push(nome); }
    porNome[nome].requisitos.push({ linha: i + 1, sistema: sistema, versaoMinima: versaoMinima });
  }
  return ordem.map(function (n) { return porNome[n]; });
}

function criarCampanha(nome, requisitos) {
  exigirAdmin_();
  nome = String(nome || '').trim();
  if (!nome) { throw new Error('Informe um nome de campanha.'); }
  if (!requisitos || !requisitos.length) { throw new Error('Adicione pelo menos um sistema/versao.'); }

  var aba = obterAbaCampanhas_();
  var idx = obterCabecalhoCampanhas_(aba);
  var totalColunas = aba.getLastColumn();
  var dados = aba.getDataRange().getValues();
  for (var i = 1; i < dados.length; i++) {
    if (String(dados[i][idx.campanha]).trim().toLowerCase() === nome.toLowerCase()) {
      throw new Error('Ja existe uma campanha com esse nome.');
    }
  }

  var linhasNovas = requisitos.map(function (r) {
    var linha = new Array(totalColunas).fill('');
    linha[idx.campanha] = nome;
    linha[idx.sistema] = validarSistemaPermitido_(r.sistema);
    linha[idx.versaoMinima] = validarVersaoMinima_(r.versaoMinima);
    linha[idx.ativo] = 'TRUE';
    linha[idx.padraoTv] = 'FALSE'; // campanha nova nunca vira padrao do TV sozinha - admin escolhe explicitamente
    return linha;
  });
  aba.getRange(aba.getLastRow() + 1, 1, linhasNovas.length, totalColunas).setValues(linhasNovas);
  SpreadsheetApp.flush();
  return obterCampanhasAdmin();
}

function definirCampanhaPadraoTv(nome) {
  // So' UMA campanha pode ser a padrao do Painel TV por vez - marca
  // TRUE em todas as linhas de "nome" e FALSE em todas as outras
  // campanhas (nao so' desmarca a anterior - garante a invariante mesmo
  // se o estado atual estiver inconsistente por algum motivo).
  exigirAdmin_();
  nome = String(nome || '').trim();
  if (!nome) { throw new Error('Informe uma campanha.'); }
  var aba = obterAbaCampanhas_();
  var idx = obterCabecalhoCampanhas_(aba);
  var dados = aba.getDataRange().getValues();
  var achouCampanha = false;
  for (var i = 1; i < dados.length; i++) {
    var nomeLinha = String(dados[i][idx.campanha]).trim();
    if (!nomeLinha) continue;
    var ehAlvo = nomeLinha.toLowerCase() === nome.toLowerCase();
    if (ehAlvo) achouCampanha = true;
    aba.getRange(i + 1, idx.padraoTv + 1).setValue(ehAlvo ? 'TRUE' : 'FALSE');
  }
  if (!achouCampanha) { throw new Error('Campanha nao encontrada.'); }
  SpreadsheetApp.flush();
  return obterCampanhasAdmin();
}

function definirAtivoCampanha(nome, ativo) {
  exigirAdmin_();
  var aba = obterAbaCampanhas_();
  var idx = obterCabecalhoCampanhas_(aba);
  var dados = aba.getDataRange().getValues();
  var valor = ativo ? 'TRUE' : 'FALSE';
  for (var i = 1; i < dados.length; i++) {
    if (String(dados[i][idx.campanha]).trim().toLowerCase() === String(nome || '').trim().toLowerCase()) {
      aba.getRange(i + 1, idx.ativo + 1).setValue(valor);
    }
  }
  SpreadsheetApp.flush();
  return obterCampanhasAdmin();
}

function salvarRequisito(linha, sistema, versaoMinima) {
  exigirAdmin_();
  var aba = obterAbaCampanhas_();
  var idx = obterCabecalhoCampanhas_(aba);
  aba.getRange(linha, idx.sistema + 1).setValue(validarSistemaPermitido_(sistema));
  aba.getRange(linha, idx.versaoMinima + 1).setValue(validarVersaoMinima_(versaoMinima));
  SpreadsheetApp.flush();
  return obterCampanhasAdmin();
}

function adicionarRequisitoACampanha(nome, sistema, versaoMinima) {
  exigirAdmin_();
  var aba = obterAbaCampanhas_();
  var idx = obterCabecalhoCampanhas_(aba);
  var totalColunas = aba.getLastColumn();
  var dados = aba.getDataRange().getValues();
  var ativoCampanha = 'TRUE';
  var padraoTvCampanha = 'FALSE';
  var achouCampanha = false;
  for (var i = 1; i < dados.length; i++) {
    if (String(dados[i][idx.campanha]).trim().toLowerCase() === String(nome || '').trim().toLowerCase()) {
      achouCampanha = true;
      ativoCampanha = String(dados[i][idx.ativo]).trim().toUpperCase() === 'FALSE' ? 'FALSE' : 'TRUE';
      padraoTvCampanha = String(dados[i][idx.padraoTv]).trim().toUpperCase() === 'TRUE' ? 'TRUE' : 'FALSE';
      break;
    }
  }
  if (!achouCampanha) { throw new Error('Campanha nao encontrada.'); }
  var linha = new Array(totalColunas).fill('');
  linha[idx.campanha] = nome;
  linha[idx.sistema] = validarSistemaPermitido_(sistema);
  linha[idx.versaoMinima] = validarVersaoMinima_(versaoMinima);
  linha[idx.ativo] = ativoCampanha;
  linha[idx.padraoTv] = padraoTvCampanha;
  aba.getRange(aba.getLastRow() + 1, 1, 1, totalColunas).setValues([linha]);
  SpreadsheetApp.flush();
  return obterCampanhasAdmin();
}

function removerRequisito(linha) {
  exigirAdmin_();
  var aba = obterAbaCampanhas_();
  var idx = obterCabecalhoCampanhas_(aba);
  var dados = aba.getDataRange().getValues();
  if (linha < 2 || linha > dados.length) { throw new Error('Linha invalida.'); }
  var nomeCampanha = String(dados[linha - 1][idx.campanha]).trim();
  var totalRequisitosCampanha = 0;
  for (var i = 1; i < dados.length; i++) {
    if (String(dados[i][idx.campanha]).trim().toLowerCase() === nomeCampanha.toLowerCase()) { totalRequisitosCampanha++; }
  }
  if (totalRequisitosCampanha <= 1) {
    throw new Error('Nao e possivel remover o unico sistema de uma campanha - desative a campanha inteira em vez disso.');
  }
  aba.deleteRow(linha);
  SpreadsheetApp.flush();
  return obterCampanhasAdmin();
}
