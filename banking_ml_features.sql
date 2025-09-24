/* ======================================================================
README — Banking Intelligence: Feature Engineering in MySQL

OBIETTIVO
Creare una tabella di feature per modelli ML a partire dalle tabelle:
cliente, conto, tipo_conto, tipo_transazione, transazioni.
Le feature includono indicatori globali e per tipologia di conto.

REQUISITI
- MySQL 8.0+ (Workbench)
- Schema attivo: `banca`
- Tabelle minime:
  cliente(id_cliente, nome, cognome, data_nascita)
  conto(id_conto, id_cliente, id_tipo_conto)
  tipo_conto(id_tipo_conto, desc_tipo_conto)
  tipo_transazione(id_tipo_transazione, segno)   -- segno: '+' o '-'
  transazioni(id_conto, id_tipo_trans, data, importo)

OUTPUT CREATI
- features_final_simple  ← tabella denormalizzata finale (una riga per cliente)
  (contiene sia indicatori globali che colonne per tipologia)
====================================================================== */

USE banca;


/* Pulizia: rimuoviamo eventuali oggetti della versione precedente per non fare confusione. */
DROP TABLE IF EXISTS features_final_simple;
DROP TEMPORARY TABLE IF EXISTS tmp_tx;
DROP TEMPORARY TABLE IF EXISTS tmp_cliente;
DROP TEMPORARY TABLE IF EXISTS tmp_tx_global;
DROP TEMPORARY TABLE IF EXISTS tmp_conti_tot;
DROP TEMPORARY TABLE IF EXISTS tmp_tx_by_type;
DROP TEMPORARY TABLE IF EXISTS tmp_conti_by_type;
DROP TEMPORARY TABLE IF EXISTS tmp_tx_pivot;
DROP TEMPORARY TABLE IF EXISTS tmp_conti_pivot;

/* ---------------------------------------------------------------
   1) BASE TRANSAZIONI ARRICCHITA (JOIN + DIREZIONE NORMALIZZATA)
   Per evitare di rifare join in ogni step, creiamo una base unica.
---------------------------------------------------------------- */
CREATE TEMPORARY TABLE tmp_tx AS
SELECT 
  t.id_conto,
  c.id_cliente,
  c.id_tipo_conto,
  t.data,
  t.importo,
  CASE
    WHEN tt.segno = '+' THEN 'IN'
    WHEN tt.segno = '-' THEN 'OUT'
    ELSE CASE WHEN t.importo >= 0 THEN 'IN' ELSE 'OUT' END
  END AS direzione
FROM transazioni t
JOIN conto c  ON c.id_conto = t.id_conto
LEFT JOIN tipo_transazione tt ON tt.id_tipo_transazione = t.id_tipo_trans;

/* Indici minimi per velocizzare aggregazioni per cliente/tipo e filtri per data */
ALTER TABLE tmp_tx 
  ADD INDEX (id_cliente), 
  ADD INDEX (id_tipo_conto),
  ADD INDEX (data);

/* ---------------------------------------------------------------
   2) ANAGRAFICA MINIMA CLIENTE (ETÀ) — separata per chiarezza
---------------------------------------------------------------- */
CREATE TEMPORARY TABLE tmp_cliente AS
SELECT 
  id_cliente, nome, cognome,
  TIMESTAMPDIFF(YEAR, data_nascita, CURDATE()) AS eta
FROM cliente;

/* ---------------------------------------------------------------
   3) INDICATORI GLOBALI PER CLIENTE (conteggi + somme + recency)
   Usiamo ABS(importo) per avere somme positive, visto che OUT è negativa all'origine.
---------------------------------------------------------------- */
CREATE TEMPORARY TABLE tmp_tx_global AS
SELECT 
  id_cliente,
  SUM(CASE WHEN direzione='IN'  THEN 1 ELSE 0 END)            AS n_tx_in,
  SUM(CASE WHEN direzione='OUT' THEN 1 ELSE 0 END)            AS n_tx_out,
  SUM(CASE WHEN direzione='IN'  THEN ABS(importo) ELSE 0 END) AS sum_in_abs,
  SUM(CASE WHEN direzione='OUT' THEN ABS(importo) ELSE 0 END) AS sum_out_abs,
  MAX(data) AS last_tx_date
FROM tmp_tx
GROUP BY id_cliente;

/* ---------------------------------------------------------------
   4) NUMERO TOTALE DI CONTI PER CLIENTE
---------------------------------------------------------------- */
CREATE TEMPORARY TABLE tmp_conti_tot AS
SELECT id_cliente, COUNT(*) AS n_conti_tot
FROM conto
GROUP BY id_cliente;

/* ---------------------------------------------------------------
   5) TRANSAZIONI PER TIPOLOGIA DI CONTO (per cliente × tipologia)
---------------------------------------------------------------- */
CREATE TEMPORARY TABLE tmp_tx_by_type AS
SELECT 
  x.id_cliente,
  tc.desc_tipo_conto AS tipo_conto,
  SUM(CASE WHEN x.direzione='IN'  THEN 1 ELSE 0 END)            AS n_tx_in,
  SUM(CASE WHEN x.direzione='OUT' THEN 1 ELSE 0 END)            AS n_tx_out,
  SUM(CASE WHEN x.direzione='IN'  THEN ABS(x.importo) ELSE 0 END) AS sum_in_abs,
  SUM(CASE WHEN x.direzione='OUT' THEN ABS(x.importo) ELSE 0 END) AS sum_out_abs
FROM tmp_tx x
JOIN tipo_conto tc ON tc.id_tipo_conto = x.id_tipo_conto
GROUP BY x.id_cliente, tc.desc_tipo_conto;

/* ---------------------------------------------------------------
   6) NUMERO CONTI PER TIPOLOGIA (per cliente × tipologia)
---------------------------------------------------------------- */
CREATE TEMPORARY TABLE tmp_conti_by_type AS
SELECT 
  c.id_cliente,
  tc.desc_tipo_conto AS tipo_conto,
  COUNT(*) AS n_conti
FROM conto c
JOIN tipo_conto tc ON tc.id_tipo_conto = c.id_tipo_conto
GROUP BY c.id_cliente, tc.desc_tipo_conto;

/* ---------------------------------------------------------------
   7) PIVOT "STATICA" IN COLONNE
---------------------------------------------------------------- */

/* 7a) Pivot transazioni per tipologia */
CREATE TEMPORARY TABLE tmp_tx_pivot AS
SELECT 
  id_cliente,

  /* Conto Base */
  SUM(CASE WHEN tipo_conto='Conto Base' THEN n_tx_in     ELSE 0 END) AS n_tx_in_conto_base,
  SUM(CASE WHEN tipo_conto='Conto Base' THEN n_tx_out    ELSE 0 END) AS n_tx_out_conto_base,
  SUM(CASE WHEN tipo_conto='Conto Base' THEN sum_in_abs  ELSE 0 END) AS sum_in_abs_conto_base,
  SUM(CASE WHEN tipo_conto='Conto Base' THEN sum_out_abs ELSE 0 END) AS sum_out_abs_conto_base,

  /* Conto Privati */
  SUM(CASE WHEN tipo_conto='Conto Privati' THEN n_tx_in     ELSE 0 END) AS n_tx_in_conto_privati,
  SUM(CASE WHEN tipo_conto='Conto Privati' THEN n_tx_out    ELSE 0 END) AS n_tx_out_conto_privati,
  SUM(CASE WHEN tipo_conto='Conto Privati' THEN sum_in_abs  ELSE 0 END) AS sum_in_abs_conto_privati,
  SUM(CASE WHEN tipo_conto='Conto Privati' THEN sum_out_abs ELSE 0 END) AS sum_out_abs_conto_privati,

  /* Conto Business */
  SUM(CASE WHEN tipo_conto='Conto Business' THEN n_tx_in     ELSE 0 END) AS n_tx_in_conto_business,
  SUM(CASE WHEN tipo_conto='Conto Business' THEN n_tx_out    ELSE 0 END) AS n_tx_out_conto_business,
  SUM(CASE WHEN tipo_conto='Conto Business' THEN sum_in_abs  ELSE 0 END) AS sum_in_abs_conto_business,
  SUM(CASE WHEN tipo_conto='Conto Business' THEN sum_out_abs ELSE 0 END) AS sum_out_abs_conto_business,

  /* Conto Famiglie */
  SUM(CASE WHEN tipo_conto='Conto Famiglie' THEN n_tx_in     ELSE 0 END) AS n_tx_in_conto_famiglie,
  SUM(CASE WHEN tipo_conto='Conto Famiglie' THEN n_tx_out    ELSE 0 END) AS n_tx_out_conto_famiglie,
  SUM(CASE WHEN tipo_conto='Conto Famiglie' THEN sum_in_abs  ELSE 0 END) AS sum_in_abs_conto_famiglie,
  SUM(CASE WHEN tipo_conto='Conto Famiglie' THEN sum_out_abs ELSE 0 END) AS sum_out_abs_conto_famiglie

FROM tmp_tx_by_type
GROUP BY id_cliente;

/* 7b) Pivot numero conti per tipologia */
CREATE TEMPORARY TABLE tmp_conti_pivot AS
SELECT 
  id_cliente,
  SUM(CASE WHEN tipo_conto='Conto Base'     THEN n_conti ELSE 0 END) AS n_conti_conto_base,
  SUM(CASE WHEN tipo_conto='Conto Privati'  THEN n_conti ELSE 0 END) AS n_conti_conto_privati,
  SUM(CASE WHEN tipo_conto='Conto Business' THEN n_conti ELSE 0 END) AS n_conti_conto_business,
  SUM(CASE WHEN tipo_conto='Conto Famiglie' THEN n_conti ELSE 0 END) AS n_conti_conto_famiglie
FROM tmp_conti_by_type
GROUP BY id_cliente;

/* ---------------------------------------------------------------
   8) JOIN FINALE — UNA RIGA PER CLIENTE (zeri con COALESCE)
---------------------------------------------------------------- */
CREATE TABLE features_final_simple AS
SELECT 
  b.id_cliente, b.nome, b.cognome, b.eta,

  /* GLOBALI */
  COALESCE(g.n_tx_in,0)      AS n_tx_in,
  COALESCE(g.n_tx_out,0)     AS n_tx_out,
  COALESCE(g.sum_in_abs,0)   AS sum_in_abs,
  COALESCE(g.sum_out_abs,0)  AS sum_out_abs,
  COALESCE(ct.n_conti_tot,0) AS n_conti_tot,

  g.last_tx_date,
  CASE WHEN g.last_tx_date IS NULL THEN NULL
       ELSE DATEDIFF(CURDATE(), g.last_tx_date)
  END AS days_since_last_tx,

  /* CONTI PER TIPOLOGIA (0 se assenti) */
  COALESCE(cp.n_conti_conto_base,0)      AS n_conti_conto_base,
  COALESCE(cp.n_conti_conto_privati,0)   AS n_conti_conto_privati,
  COALESCE(cp.n_conti_conto_business,0)  AS n_conti_conto_business,
  COALESCE(cp.n_conti_conto_famiglie,0)  AS n_conti_conto_famiglie,

  /* TX PER TIPOLOGIA (0 se assenti) */
  COALESCE(tp.n_tx_in_conto_base,0)        AS n_tx_in_conto_base,
  COALESCE(tp.n_tx_out_conto_base,0)       AS n_tx_out_conto_base,
  COALESCE(tp.sum_in_abs_conto_base,0)     AS sum_in_abs_conto_base,
  COALESCE(tp.sum_out_abs_conto_base,0)    AS sum_out_abs_conto_base,

  COALESCE(tp.n_tx_in_conto_privati,0)     AS n_tx_in_conto_privati,
  COALESCE(tp.n_tx_out_conto_privati,0)    AS n_tx_out_conto_privati,
  COALESCE(tp.sum_in_abs_conto_privati,0)  AS sum_in_abs_conto_privati,
  COALESCE(tp.sum_out_abs_conto_privati,0) AS sum_out_abs_conto_privati,

  COALESCE(tp.n_tx_in_conto_business,0)    AS n_tx_in_conto_business,
  COALESCE(tp.n_tx_out_conto_business,0)   AS n_tx_out_conto_business,
  COALESCE(tp.sum_in_abs_conto_business,0) AS sum_in_abs_conto_business,
  COALESCE(tp.sum_out_abs_conto_business,0)AS sum_out_abs_conto_business,

  COALESCE(tp.n_tx_in_conto_famiglie,0)    AS n_tx_in_conto_famiglie,
  COALESCE(tp.n_tx_out_conto_famiglie,0)   AS n_tx_out_conto_famiglie,
  COALESCE(tp.sum_in_abs_conto_famiglie,0) AS sum_in_abs_conto_famiglie,
  COALESCE(tp.sum_out_abs_conto_famiglie,0)AS sum_out_abs_conto_famiglie

FROM tmp_cliente b
LEFT JOIN tmp_tx_global   g  USING(id_cliente)
LEFT JOIN tmp_conti_tot   ct USING(id_cliente)
LEFT JOIN tmp_conti_pivot cp USING(id_cliente)
LEFT JOIN tmp_tx_pivot    tp USING(id_cliente);

/* Indice utile per filtri/merge su id_cliente */
CREATE INDEX idx_ff_simple_id ON features_final_simple(id_cliente);

/* ---------------------------------------------------------------
   9) QC
---------------------------------------------------------------- */
-- Una riga per cliente?
SELECT COUNT(*) AS righe, COUNT(DISTINCT id_cliente) AS clienti FROM features_final_simple;

-- Coerenza: globali vs somma per tipologia (deve restituire 0 righe)
SELECT id_cliente
FROM features_final_simple
WHERE n_tx_in  <> (n_tx_in_conto_base  + n_tx_in_conto_privati  + n_tx_in_conto_business  + n_tx_in_conto_famiglie)
   OR n_tx_out <> (n_tx_out_conto_base + n_tx_out_conto_privati + n_tx_out_conto_business + n_tx_out_conto_famiglie)
LIMIT 10;


/* ---------------------------------------------------------------
   10) REPORT RAPIDI — visualizzare il risultato
---------------------------------------------------------------- */

-- 10.1 Anteprima tabella finale
SELECT * 
FROM features_final_simple 
ORDER BY id_cliente
LIMIT 20;

-- 10.2 Clienti con maggiore spesa in uscita (sum_out_abs)
SELECT id_cliente, nome, cognome, n_tx_out, ROUND(sum_out_abs,2) AS sum_out_abs, n_conti_tot
FROM features_final_simple
ORDER BY sum_out_abs DESC
LIMIT 10;

-- 10.3 Clienti "dormienti" (nessuna transazione recente o mai)
SELECT id_cliente, nome, cognome, last_tx_date, days_since_last_tx
FROM features_final_simple
WHERE last_tx_date IS NULL OR days_since_last_tx > 365
ORDER BY days_since_last_tx DESC
LIMIT 10;

-- 10.4 Profilo per singolo cliente (sostituisci 123 con l'id che vuoi guardare)
SELECT *
FROM features_final_simple
WHERE id_cliente = 123;

-- 10.5 Totali per TIPOLOGIA (wide -> long via UNION ALL): n_tx, importi
SELECT 'Conto Base'     AS tipo,
       SUM(n_tx_in_conto_base)     AS n_tx_in,
       SUM(n_tx_out_conto_base)    AS n_tx_out,
       ROUND(SUM(sum_in_abs_conto_base),2)  AS sum_in_abs,
       ROUND(SUM(sum_out_abs_conto_base),2) AS sum_out_abs
FROM features_final_simple
UNION ALL
SELECT 'Conto Privati',
       SUM(n_tx_in_conto_privati),  SUM(n_tx_out_conto_privati),
       ROUND(SUM(sum_in_abs_conto_privati),2), ROUND(SUM(sum_out_abs_conto_privati),2)
FROM features_final_simple
UNION ALL
SELECT 'Conto Business',
       SUM(n_tx_in_conto_business), SUM(n_tx_out_conto_business),
       ROUND(SUM(sum_in_abs_conto_business),2), ROUND(SUM(sum_out_abs_conto_business),2)
FROM features_final_simple
UNION ALL
SELECT 'Conto Famiglie',
       SUM(n_tx_in_conto_famiglie), SUM(n_tx_out_conto_famiglie),
       ROUND(SUM(sum_in_abs_conto_famiglie),2), ROUND(SUM(sum_out_abs_conto_famiglie),2)
FROM features_final_simple;

-- 10.6 Copertura tipologie: % clienti che possiedono almeno un conto di quel tipo
SELECT 
  ROUND(100.0 * SUM(n_conti_conto_base     > 0) / COUNT(*), 1) AS pct_conto_base,
  ROUND(100.0 * SUM(n_conti_conto_privati  > 0) / COUNT(*), 1) AS pct_conto_privati,
  ROUND(100.0 * SUM(n_conti_conto_business > 0) / COUNT(*), 1) AS pct_conto_business,
  ROUND(100.0 * SUM(n_conti_conto_famiglie > 0) / COUNT(*), 1) AS pct_conto_famiglie
FROM features_final_simple;

