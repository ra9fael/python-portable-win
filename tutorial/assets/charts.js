(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();

  var el = document.getElementById('chart-size');
  if (!el || !window.echarts) { return; }

  function currentLang() {
    return document.documentElement.lang === 'en' ? 'en' : 'zh';
  }

  function labels(lang) {
    if (lang === 'en') {
      return {
        names: ['Interpreter + stdlib', 'site-packages', 'scripts / app'],
        subtext: 'unpacked total',
        series: 'Size breakdown'
      };
    }
    return {
      names: ['解释器 + 标准库', 'site-packages', 'scripts / app'],
      subtext: '解压后总计',
      series: '体积构成'
    };
  }

  var chart = echarts.init(el, null, { renderer: 'svg' });
  var initial = labels(currentLang());

  chart.setOption({
    animation: false,
    color: [accent, accent2, muted],
    title: {
      text: '33.07 MB',
      subtext: initial.subtext,
      left: 'center',
      top: '42%',
      textStyle: { color: ink, fontSize: 22, fontWeight: 700 },
      subtextStyle: { color: muted, fontSize: 12 }
    },
    tooltip: {
      trigger: 'item',
      appendToBody: true,
      formatter: function (p) {
        return p.name + '<br/>' + p.value + ' MB · ' + p.percent + '%';
      }
    },
    legend: {
      bottom: 8,
      left: 'center',
      itemWidth: 10,
      itemHeight: 10,
      textStyle: { color: muted, fontSize: 12 }
    },
    series: [
      {
        name: initial.series,
        type: 'pie',
        radius: ['52%', '74%'],
        center: ['50%', '48%'],
        avoidLabelOverlap: true,
        itemStyle: {
          borderColor: bg2,
          borderWidth: 2
        },
        label: { show: false },
        labelLine: { show: false },
        data: [
          { value: 23.54, name: initial.names[0] },
          { value: 9.51, name: initial.names[1] },
          { value: 0.02, name: initial.names[2] }
        ]
      }
    ]
  });

  function applyChartLang(lang) {
    var next = labels(lang === 'en' ? 'en' : 'zh');
    chart.setOption({
      title: { subtext: next.subtext },
      series: [
        {
          name: next.series,
          data: [
            { value: 23.54, name: next.names[0] },
            { value: 9.51, name: next.names[1] },
            { value: 0.02, name: next.names[2] }
          ]
        }
      ]
    });
    chart.resize();
  }

  window.addEventListener('tutorial:lang', function (event) {
    applyChartLang(event.detail && event.detail.lang);
  });

  window.addEventListener('resize', function () { chart.resize(); });
})();
