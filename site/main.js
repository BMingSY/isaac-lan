"use strict";

const floorMap = document.querySelector("#floor-map");
const mapCaption = document.querySelector("#map-caption");
const mapControls = document.querySelector(".map-controls");
const mapModes = {
    split: {
        description: "联机方式示意：四名玩家分散在同一层的不同房间",
        caption: "分房探索，同一层里的每个人都有自己的方向。",
    },
    together: {
        description: "联机方式示意：四名玩家在 Boss 房门前的同一个房间汇合",
        caption: "找到队友，汇合后一起迎战下一个 Boss。",
    },
};

mapControls.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => {
        const mode = button.dataset.mode;
        const content = mapModes[mode];
        floorMap.dataset.mode = mode;
        floorMap.setAttribute("aria-label", content.description);
        mapCaption.textContent = content.caption;
        mapControls.querySelectorAll("button").forEach((control) => {
            control.setAttribute("aria-pressed", String(control === button));
        });
    });
});

mapControls.hidden = false;
