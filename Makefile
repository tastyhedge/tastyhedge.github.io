# More details on how to pair TailwindCSS with Hugo is here:
#
#   https://bshelling.medium.com/designing-for-speed-and-simplicity-tailwind-css-and-hugo-the-perfect-pair-da21f3506942
#
hugo-serve:
	./bin/hugo.exe server
tailwind-serve:
	cd static && ../bin/tailwindcss.exe -i src/style.css -o css/style.css --watch
