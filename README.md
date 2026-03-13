# Brazilian E-Commerce SQL Analysis in DuckDB

This project explores 100K rows of e-commerce transactions in Brazil using DuckDB.

## Dataset:
- Download at: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce/data

## setup tips:
- Download all CSV files from Kaggle (9)
- Create a new folder in your desktop
- Create a subfolder called data and put the 9 CSVs in it.
- Install DuckDB in CLI (terminal), see how to below
- Then in CLI run "duckdb brazil_ecom.db -ui"
- DuckDB UI should then open in a browser (the name brazil_ecom isn't mandatory, choose the name you want)

## 📁 Files
- `brazil_ecom.db` — the DuckDB file you can open with `duckdb brazil_ecom.db --ui`
- `data/` — contains the raw CSV files from Kaggle
- `notebooks/` — (optional) SQL code in notebook format

## Code
You'll find all the SQL code in the 'ecommerce_analysis.sql' file in this repository

## 🚀 How to use
1. Install DuckDB via Homebrew: `brew install duckdb`
2. Run: `duckdb brazil_ecom.db --ui`
3. Start querying!

Watch the full tutorial on YouTube: Anas Riad
