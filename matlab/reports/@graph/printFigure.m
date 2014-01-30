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
%if isempty(o.graphSize)
%    h = figure('visible','off');
%else
%    h = figure('visible','off','position',[1, 1, o.graphSize(1), o.graphSize(2)]);
%end
%hold on;
%box on;

if isempty(o.xrange)
    dd = o.seriesElements.getMaxRange();
else
    dd = o.xrange;
end

ne = o.seriesElements.numSeriesElements();
ymax = zeros(ne, 1);
ymin = zeros(ne, 1);
for i=1:ne
    o.seriesElements(i).writeLine(fid, dd);
    ymax(i) = o.seriesElements(i).ymax(dd);
    ymin(i) = o.seriesElements(i).ymin(dd);
end
ymax = ceil(max(ymax));
ymin = floor(min(ymin));

if o.showGrid
    fprintf(fid, '\\draw[style=help lines] (1,%d) grid (%d,%d);\n', ymin, dd.ndat, ymax);
end

if o.showZeroline
    fprintf(fid, '\\draw (1,0) -- (%d,0);\n', dd.ndat);
end

fprintf(fid, '\\draw (1,%d) -- (1,%d);\n', ymin, ymax);
fprintf(fid, '\\draw (1,%d) -- (%d,%d);\n', ymax, dd.ndat, ymax);
fprintf(fid, '\\draw (1,%d) -- (%d,%d);\n', ymin, dd.ndat, ymin);
fprintf(fid, '\\draw (%d,%d) -- (%d,%d);\n', dd.ndat, ymin, dd.ndat, ymax);

if ~isempty(o.yrange)
    fprintf(fid, '\\clip (1,%f) rectangle (%d, %f);\n', o.yrange(1), ...
            dd.ndat, o.yrange(2));
end

x = 1:1:dd.ndat;
xlabels = strings(dd);
if ~isempty(o.shade)
    x1 = find(strcmpi(date2string(o.shade(1)), xlabels));
    x2 = find(strcmpi(date2string(o.shade(end)), xlabels));
    assert(~isempty(x1) && ~isempty(x2), ['@graph.createGraph: either ' ...
                        date2string(o.shade(1)) ' or ' date2string(o.shade(end)) ' is not in the date ' ...
                        'range of data selected.']);
    fprintf(fid, '\\begin{pgfonlayer}{background}\n');
    fprintf(fid, ['  \\fill[green!20!white] '...
                  '(%d,%d) -- (%d, %d) -- (%d, %d) -- (%d, %d) -- cycle;\n'...
                  ''], x1, ymin, x1, ymax, x2, ymax, x2, ymin);
    fprintf(fid, '\\end{pgfonlayer}\n');
end


fprintf(fid, '\n\\end{tikzpicture}\n');
status = fclose(fid);
if status == -1
    error('@graph.printFigure: closing %s\n', o.filename);
end
return

if isempty(o.xTickLabels)
    xticks = get(gca, 'XTick');
    xTickLabels = cell(1, length(xticks));
    for i=1:length(xticks)
        if xticks(i) >= x(1) && ...
                xticks(i) <= x(end)
            xTickLabels{i} = xlabels{xticks(i)};
        else
            xTickLabels{i} = '';
        end
    end
else
    set(gca, 'XTick', o.xTicks);
    xTickLabels = o.xTickLabels;
end
set(gca, 'XTickLabel', xTickLabels);

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

if ~isempty(o.xlabel)
    xlabel(['$\textbf{\footnotesize ' o.xlabel '}$'], 'Interpreter', 'LaTex');
end

if ~isempty(o.ylabel)
    ylabel(['$\textbf{\footnotesize ' o.ylabel '}$'], 'Interpreter', 'LaTex');
end
drawnow;


disp('  converting to tex....');
if isoctave && isempty(regexpi(computer, '.*apple.*', 'once'))
    print(o.figname, '-dtikz');
else
    matlab2tikz('filename', o.figname, ...
                'showInfo', false, ...
                'showWarnings', false, ...
                'checkForUpdates', false);
end

end
