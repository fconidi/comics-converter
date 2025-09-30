# COMICS CONVERTER


Comics converter for cbr, cbz, pdf



<img width="1536" height="1024" alt="comics" src="https://github.com/user-attachments/assets/f34f265d-c92b-4ee2-81ce-6cab650937b8" />






This Bash script, named Comics Converter, is designed to convert digital comic book files in PDF, CBZ (ZIP), and CBR (RAR) formats into unified PDF files, with the internal images converted to JPEG format. It uses common command-line tools and the Zenity GUI utility for user interaction and error/warning reporting.

This program is the evolution of AllCbrztoPdf, which I created some time ago, but it had limitations. The program would sometimes fail for a variety of reasons, both intentional and unintentional on the part of the file creator. Below are some examples:

    The name of the extracted file was too long, causing the script to fail.

    The images were mostly JPEG, but a couple or more had different extensions.

    Some CBR files had been intentionally (in my opinion) renamed from CBR to CBZ and vice versa.

    Besides the length issue, some characters in the names also caused problems.

    The file name/number sequence for the jpg/png files generated pagination problems during conversion.

Comics Converter solves the above issues, starting from the basics, namely by using progressive numbering starting from 001 and removing any initial numbering. It solves the fake extension problem by verifying it and renaming the file correctly if necessary. It only retains the original file's base name.

Prerequisites

Before running the script, you must ensure you have the following system tools installed, as they are required by the script:

    pdfimages: Part of the Poppler package, used to extract images from PDFs.

    convert: Part of ImageMagick, used to convert image formats to JPEG.

    img2pdf: Used to convert individual images into PDFs.

    pdftk (or equivalent if unavailable): Used to merge the PDFs of the individual pages.

    unzip: Used to extract CBZ (ZIP) archives.

    zenity: Used for graphical dialogue boxes (directory selection, errors, warnings, info).

    head: Used to read the start of files for the magic bytes.

    xxd: Used to display the magic bytes in hexadecimal.

    unrar OR 7z (p7zip): Needed to extract CBR (RAR) archives. The script checks for the presence of both and uses one.

If any are missing, the script will notify the user via Zenity and exit.

DOWNLOAD

<code> 
git clone https://github.com/fconidi/comics-converter.git
cd comics-converter/
chmod +x comics_converter.sh
./comics_converter.sh
</code>

enjoy ;)

