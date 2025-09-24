# Bank-customer-analysis

# Banking Intelligence: Feature Engineering in MySQL

## Obiettivo
Creare una **tabella di feature** per modelli di Machine Learning a partire dalle tabelle del database:  
`cliente`, `conto`, `tipo_conto`, `tipo_transazione`, `transazioni`.  

Le feature includono:  
- Indicatori **globali** (sintesi sul comportamento complessivo del cliente).  
- Indicatori **per tipologia di conto** (colonne dedicate).  

---

## Requisiti
- **MySQL 8.0+** (Workbench consigliato).  
- Schema attivo: **`banca`**.  

### Tabelle minime richieste
- **cliente**  
  ```sql
  cliente(
    id_cliente INT PRIMARY KEY,
    nome VARCHAR,
    cognome VARCHAR,
    data_nascita DATE
  )
