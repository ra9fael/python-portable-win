(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();

  if (window.mermaid) {
    mermaid.initialize({
      startOnLoad: true,
      theme: 'base',
      themeVariables: {
        primaryColor: bg2,
        primaryTextColor: ink,
        primaryBorderColor: accent,
        lineColor: muted,
        fontFamily: "'Instrument Sans', 'Microsoft YaHei', sans-serif",
        fontSize: '14px',
        clusterBkg: '#fbfaf6',
        clusterBorder: rule
      },
      flowchart: { curve: 'basis', useMaxWidth: true }
    });
  }

  var el = document.getElementById('chart-size');
  if (!el || !window.echarts) { return; }

  var isEn = (document.documentElement.lang || '').toLowerCase().indexOf('en') === 0;
  var names = isEn
    ? ['Interpreter + stdlib', 'site-packages', 'scripts / app']
    : ['解释器 + 标准库', 'site-packages', 'scripts / app'];

  var chart = echarts.init(el, null, { renderer: 'svg' });
  chart.setOption({
    animation: false,
    color: [accent, accent2, muted],
    title: {
      text: '33.07 MB',
      subtext: isEn ? 'unpacked total' : '解压后总计',
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
        name: isEn ? 'Size breakdown' : '体积构成',
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
          { value: 23.54, name: names[0] },
          { value: 9.51, name: names[1] },
          { value: 0.02, name: names[2] }
        ]
      }
    ]
  });

  window.addEventListener('resize', function () { chart.resize(); });
})();
