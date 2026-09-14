# Das Dokument laedt luainputenc, deshalb ist LuaLaTeX die richtige Engine.
# pdflatex bricht mit "LuaTeX required" ab.
$pdf_mode = 4;            # 4 = lualatex

# Bibliografie: main.tex setzt backend=biber, latexmk erkennt das an der .bcf
# und ruft biber selbst auf. Der Wert sorgt zusaetzlich dafuer, dass .bbl
# beim Aufraeumen mit entfernt wird.
$bibtex_use = 2;

# Zwischendateien, die latexmk nicht von Haus aus kennt
$clean_ext = 'run.xml synctex.gz bbl';
