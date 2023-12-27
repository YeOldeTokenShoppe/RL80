document.addEventListener("DOMContentLoaded", function() {
    const flame = document.querySelector(".flame");
    const glow = document.querySelector(".glow");
    const blinkingGlow = document.querySelector(".blinking-glow");
    const toggleButton = document.getElementById("toggleFlame");

    // Initially hide the flame and its associated elements
    flame.style.display = "none";
    glow.style.display = "none";
    blinkingGlow.style.display = "none";

    toggleButton.addEventListener("click", function() {
        if (flame.style.display === "none") {
            flame.style.display = "block";
            glow.style.display = "block";
            blinkingGlow.style.display = "block";
        } else {
            flame.style.display = "none";
            glow.style.display = "none";
            blinkingGlow.style.display = "none";
        }
    });
});



let btn = document.querySelector("button");
setTimeout(() => {
    btn.classList.remove("active");
},1400);

document.querySelector('#toggleFlame').addEventListener('click', function() {
    document.body.classList.toggle('gradient-background');
  });