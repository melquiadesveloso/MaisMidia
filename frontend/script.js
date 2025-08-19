class MediaPlayer {
  constructor() {
    this.academyId = new URLSearchParams(location.search).get("academy_id") || "default";
    this.apiBase = "REPLACE_WITH_API_URL"; // ex: https://xxxx.execute-api.us-east-1.amazonaws.com/prod
    this.mediaList = [];
    this.index = 0;
    this.cfg = { interval: 10, loop: true };

    this.imgEl = document.getElementById("media-image");
    this.vidEl = document.getElementById("media-video");
    this.nameEl = document.getElementById("academy-name");
    this.curEl = document.getElementById("current-index");
    this.totalEl = document.getElementById("total-items");

    this.init();
  }
  

  async init() {
    try {
      this.showLoading();
      const data = await this.fetchPlaylist();
      this.mediaList = data.media_list || [];
      this.cfg = Object.assign(this.cfg, data.playlist_config || {});
      this.nameEl.textContent = this.cfg.academy_name || "Academia";
      this.totalEl.textContent = this.mediaList.length;
      if (!this.mediaList.length) throw new Error("Nenhuma mídia encontrada");
      this.hideLoading();
      this.play();
    } catch (e) {
      this.showError(e.message || String(e));
    }
  }

  async fetchPlaylist() {
    const url = `${this.apiBase}/academies/${encodeURIComponent(this.academyId)}/playlist`;
    const resp = await fetch(url, { cache: "no-store" });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
  }

  play() {
    if (!this.mediaList.length) return;
    this.showMedia(this.mediaList[this.index]);
  }

  showMedia(item) {
    this.curEl.textContent = this.index + 1;
    if (item.type === "video") {
      this.playVideo(item.url);
    } else {
      this.playImage(item.url);
    }
  }

  playImage(url) {
    const img = new Image();
    img.onload = () => {
      this.imgEl.src = url;
      this.imgEl.classList.remove("hidden");
      this.vidEl.classList.add("hidden");
      setTimeout(() => this.next(), (this.cfg.interval || 10) * 1000);
    };
    img.onerror = () => this.next();
    img.src = url;
  }

  playVideo(url) {
    this.vidEl.src = url;
    this.vidEl.onloadeddata = () => {
      this.vidEl.play().catch(() => this.next());
    };
    this.vidEl.onended = () => setTimeout(() => this.next(), (this.cfg.interval || 10) * 1000);
    this.vidEl.onerror = () => this.next();
    this.vidEl.classList.remove("hidden");
    this.imgEl.classList.add("hidden");
  }

  next() {
    this.index += 1;
    if (this.index >= this.mediaList.length) {
      if (this.cfg.loop) this.index = 0; else return;
    }
    this.play();
  }

  showLoading() {
    document.getElementById("loading").classList.remove("hidden");
    document.getElementById("media-display").classList.add("hidden");
    document.getElementById("error-display").classList.add("hidden");
  }
  hideLoading() {
    document.getElementById("loading").classList.add("hidden");
    document.getElementById("media-display").classList.remove("hidden");
  }
  showError(msg) {
    document.getElementById("loading").classList.add("hidden");
    document.getElementById("media-display").classList.add("hidden");
    document.getElementById("error-display").classList.remove("hidden");
    document.getElementById("error-message").textContent = msg;
  }
}

function retryLoad(){ location.reload(); }

window.addEventListener("DOMContentLoaded", () => new MediaPlayer());



