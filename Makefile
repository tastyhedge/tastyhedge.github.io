# More details on how to pair TailwindCSS with Hugo is here:
#
#   https://bshelling.medium.com/designing-for-speed-and-simplicity-tailwind-css-and-hugo-the-perfect-pair-da21f3506942
#

.PHONY: build css deploy serve sync

serve:
	./bin/hugo.exe server --buildDrafts
build:
	rm public/ -rf && ./bin/hugo.exe
deploy: build sync
sync:
	aws s3 sync --size-only --delete ./public/ s3://tastyhedge.com/

css:
	./bin/tailwindcss.exe -i main.css -o static/css/main.css --watch --content "layouts/**/*.html"
