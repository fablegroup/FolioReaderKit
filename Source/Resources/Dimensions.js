
function getContentDimensions() {
    let sWidth = document.documentElement.scrollWidth
    let sHeight = document.documentElement.scrollHeight
    let sLeft = window.pageXOffset
    let sTop = window.pageYOffset
    let vWidth = document.documentElement.clientWidth
    let vHeight = document.documentElement.clientHeight
    
    return { scrollWidth : sWidth, scrollHeight: sHeight, scrollLeft : sLeft, scrollTop : sTop, viewportWidth: vWidth, viewportHeight: vHeight }
}
