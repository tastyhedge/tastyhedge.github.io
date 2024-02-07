# More details on how to pair TailwindCSS with Hugo is here:
#
#   https://bshelling.medium.com/designing-for-speed-and-simplicity-tailwind-css-and-hugo-the-perfect-pair-da21f3506942
#

hugo:
	rm public/ -rf && ./bin/hugo.exe
hugo-serve:
	./bin/hugo.exe server  --disableFastRender
tailwind-serve:
	cd static && ../bin/tailwindcss.exe -i src/style.css -o css/style.css --watch

s3-sync:
	aws s3 sync --size-only ./public/ s3://tastyhedge.com/
