/*
  Porta pra JS de Compare-VersaoSistema/Get-VersaoInstaladaPorNomeSistema
  (VisaoJanelaCampanhas.psm1, Visao Desktop) - MESMA logica de "atende
  a campanha" que o tecnico ja ve no Desktop (Show-JanelaVerificarCampanha):
  pra cada requisito, precisa ter o sistema instalado E a versao
  instalada >= versao minima exigida (comparacao numerica segmento a
  segmento, "1.9" < "1.10"). Maquina "pronta" = atende TODOS os
  requisitos da campanha (E logico).

  Divida tecnica (documentada no plano splendid-enchanting-mochi.md):
  o mapa dos 9 sistemas precisa ser replicado aqui porque o Apps
  Script nao acessa Get-SistemasEleitoraisExtra do servidor
  PowerShell (VisaoServidor.ps1) diretamente - se um 10o sistema for
  adicionado la, lembrar de espelhar aqui tambem.
*/
var SISTEMAS_ELEITORAIS_EXTRA = [
  { chave: "BITLOCKER", nomeVersaoAtual: "CRIPTOSIS", coluna: "Bitlocker", titulo: "Criptosis" },
  { chave: "GEDAI", nomeVersaoAtual: "GEDAI-UE", coluna: "Gedai", titulo: "GEDAI-UE" },
  { chave: "HOLOCRON", nomeVersaoAtual: "HOLOCRON", coluna: "Holocron", titulo: "Holocron" },
  { chave: "PADA-UE", nomeVersaoAtual: "PADA-UE", coluna: "PadaUe", titulo: "PADA-UE" },
  { chave: "FBR", nomeVersaoAtual: "FBR", coluna: "Fbr", titulo: "FBR" },
  { chave: "TRANSPORTADORTDTOT", nomeVersaoAtual: "TRANSPORTADOR TDTOT", coluna: "TransportadorTdtot", titulo: "Transportador TDTOT" },
  { chave: "EXECJAVA", nomeVersaoAtual: "EXECJAVA", coluna: "ExecJava", titulo: "ExecJava" },
  { chave: "TRANSPORTADOR-HMG", nomeVersaoAtual: "TRANSPORTADOR HOMOLOGAÇÃO", coluna: "TransportadorHmg", titulo: "Transportador Homologacao" },
  { chave: "CERTIFICADO P12", nomeVersaoAtual: "CERTIFICADO P12", coluna: "CertificadoP12", titulo: "Certificado P12" }
];

function compararVersaoSistema(versaoA, versaoB) {
  if (!versaoA || !versaoB) return null;
  var a = String(versaoA).trim().split(".");
  var b = String(versaoB).trim().split(".");
  var max = Math.max(a.length, b.length);
  for (var i = 0; i < max; i++) {
    var textoA = i < a.length ? a[i] : "0";
    var textoB = i < b.length ? b[i] : "0";
    if (!/^\d+$/.test(textoA) || !/^\d+$/.test(textoB)) return null;
    var na = parseInt(textoA, 10);
    var nb = parseInt(textoB, 10);
    if (na !== nb) return na > nb ? 1 : -1;
  }
  return 0;
}

function resolverColunaPorNomeSistema_(nomeSistema) {
  if (!nomeSistema) return null;
  var nomeUpper = String(nomeSistema).trim().toUpperCase();
  if (nomeUpper === "SIS") return "VersaoSis"; // caso especial - coluna generica, nao esta na lista acima
  for (var i = 0; i < SISTEMAS_ELEITORAIS_EXTRA.length; i++) {
    var item = SISTEMAS_ELEITORAIS_EXTRA[i];
    if (item.nomeVersaoAtual.toUpperCase() === nomeUpper || item.titulo.toUpperCase() === nomeUpper || item.chave.toUpperCase() === nomeUpper) {
      return item.coluna;
    }
  }
  return null;
}

function maquinaAtendeCampanha_(linhaInventario, requisitos) {
  if (!requisitos || !requisitos.length) return false;
  for (var i = 0; i < requisitos.length; i++) {
    var coluna = resolverColunaPorNomeSistema_(requisitos[i].sistema);
    var instalado = coluna ? linhaInventario[coluna] : null;
    if (!instalado || instalado === "-") return false;
    var cmp = compararVersaoSistema(instalado, requisitos[i].versaoMinima);
    if (cmp === null || cmp < 0) return false;
  }
  return true;
}
