document.addEventListener("DOMContentLoaded", function() {
    document.querySelectorAll("nav>section section").forEach((section) => {
        section.setAttribute("data-collapsed-state", "expanded");

        // the click handler goes on the *header*, not on the section itself
        section.firstElementChild.addEventListener("click", function() {
            const currentState = section.getAttribute("data-collapsed-state");
            if (currentState === "expanded") {
                section.setAttribute("data-collapsed-state", "collapsed");
            } else {
                section.setAttribute("data-collapsed-state", "expanded");
            }
        })
    })
})