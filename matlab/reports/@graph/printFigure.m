function o = printFigure(o)
%function o = printFigure(o)
% Create the graph
%
% INPUTS
%   o   [graph] graph object
%
% OUTPUTS
%   o   [graph] graph object
%
% SPECIAL REQUIREMENTS
%   none

% Copyright (C) 2013-2014 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

if ~o.seriesElements.numSeriesElements()
    warning('@graph.crepateGraph: no series to plot, returning');
    return;
end

if isempty(o.figname)
    [junk, tn] = fileparts(tempname);
    if strcmp(computer, 'PCWIN') || strcmp(computer, 'PCWIN64')
        tn = strrep(tn, '_', '-');
    end
    o.figname = [o.figDirName '/' tn '.tex'];
end

[fid, msg] = fopen(o.figname, 'w');
if fid == -1
    error(['@graph.printFigure: ' msg]);
end

fprintf(fid, '\\begin{tikzpicture}\n');

if isempty(o.xrange)
    dd = o.seriesElements.getMaxRange();
else
    dd = o.xrange;
end

ne = o.seriesElements.numSeriesElements();
for i=1:ne
    ymax(i) = o.seriesElements(i).ymax(dd);
    ymin(i) = o.seriesElements(i).ymin(dd);
end
ymax = ceil(max(ymax));
ymin = floor(min(ymin));

fprintf(fid, '\\begin{axis}[%%\n');
if o.showGrid
    fprintf(fid, 'xmajorgrids,\nymajorgrids,\n');
end

if ~isempty(o.xlabel)
    fprintf(fid, 'xlabel=%s,\n', o.xlabel);
end

if ~isempty(o.ylabel)
    fprintf(fid, 'ylabel=%s,\n', o.ylabel);
end

% set tick labels
if isempty(o.xTickLabels)
    xTickLabels = strings(dd);
else
    xTickLabels = o.xTickLabels;
end

if ~isempty(xTickLabels)
    fprintf(fid,'minor xtick={1,2,...,%d},\n', dd.ndat);
end

fprintf(fid, ['width=6.0in,\n'...
              'height=4.5in,\n'...
              'scale only axis,\n'...
              'xmin=1,\n'...
              'xmax=%d,\n'...
              'ymin=%d,\n'...
              'ymax=%d,\n]\n'], dd.ndat, ymin, ymax);

%if ~isempty(o.yrange)
%    fprintf(fid, '\\clip (1,%f) rectangle (%d, %f);\n', ...
%            o.yrange(1), dd.ndat, o.yrange(2));
%end

if o.showZeroline
    fprintf(fid, '\\addplot[black,line width=.5,forget plot] coordinates {(1,0)(%d,0)};',dd.ndat);
end

x = 1:1:dd.ndat;
if ~isempty(o.shade)
    xTickLabels = strings(dd);
    x1 = find(strcmpi(date2string(o.shade(1)), xTickLabels));
    x2 = find(strcmpi(date2string(o.shade(end)), xTickLabels));
    assert(~isempty(x1) && ~isempty(x2), ['@graph.createGraph: either ' ...
                        date2string(o.shade(1)) ' or ' date2string(o.shade(end)) ' is not in the date ' ...
                        'range of data selected.']);
    fprintf(fid, ['\\addplot[area legend,solid,fill=green,opacity=.2,draw=black,forget plot]\n'...
                  'table[row sep=crcr]{\n'...
                  'x y\\\\\n'...
                  '%d %d\\\\\n'...
                  '%d %d\\\\\n'...
                  '%d %d\\\\\n'...
                  '%d %d\\\\\n'...
                  '};\n'], x1, ymin, x1, ymax, x2, ymax, x2, ymin);
end

for i=1:ne
    o.seriesElements(i).writeLine(fid, dd);
end

fprintf(fid, '\\end{axis}\n\\end{tikzpicture}\n');
if fclose(fid) == -1
    error('@graph.printFigure: closing %s\n', o.filename);
end
return

%if ~isempty(o.xTickLabels)
%    xTickLabels = o.xTickLabels;
%end

fprintf(fid, '\\foreach \\pos/\\label in {');
for i=1:length(x)
    fprintf(fid, '%d/%s', x(i), lower(xTickLabels{i}));
    if i~=length(x)
        fprintf(fid,',');
    end
end

fprintf(fid, ['}\n  \\draw (\\pos,%d) -- (\\pos,%f) (\\pos cm,%d) node\n'...
              '  [anchor=south,inner sep=1pt,rotate=45]  {\\label};\n'],...
        ymin, ymin - 0.1, ymin - 0.7);



if o.showLegend
    lh = legend(line_handles, o.seriesElements.getTexNames(), ...
                'orientation', o.legendOrientation, ...
                'location', o.legendLocation);
    set(lh, 'FontSize', o.legendFontSize);
    set(lh, 'interpreter', 'latex');
    if ~o.showLegendBox
        legend('boxoff');
    end
end
end
