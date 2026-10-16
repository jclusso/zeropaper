# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "pdfjs-dist", to: "pdfjs-dist.js", preload: false
pin "pdfjs-dist/web/pdf_viewer", to: "pdfjs-dist--web--pdf_viewer.js", preload: false
pin "@tailwindplus/elements", to: "@tailwindplus--elements.js" # @1.0.22
pin "confirm"
pin "morph_elements"
