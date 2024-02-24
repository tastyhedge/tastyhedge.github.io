# More details on how to pair TailwindCSS with Hugo is here:
#
#   https://bshelling.medium.com/designing-for-speed-and-simplicity-tailwind-css-and-hugo-the-perfect-pair-da21f3506942
#

serve:
	./bin/hugo.exe server --buildDrafts
build:
	rm public/ -rf && ./bin/hugo.exe
publish:
	aws s3 sync --size-only ./public/ s3://tastyhedge.com/

css:
	./bin/tailwindcss.exe -i main.css -o static/css/main.css --watch --content "layouts/**/*.html"
